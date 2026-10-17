#!/usr/bin/env bash
# Rotates the flagr OAuth secrets: the Keycloak client secret for "flagr" (realm k8s) and the
# oauth2-proxy cookie secret. Updates the Keycloak database and .env, then re-applies the
# Kubernetes Secret and restarts the affected workloads. Secret values are never printed.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/../.env"

# shellcheck source=/dev/null
source "$env_file"

for var in K3S_DB_USER K3S_DB_PASSWORD DATABASE_HOST; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: $var is not defined in .env." >&2
    exit 1
  fi
done

for command in docker kubectl openssl python3 curl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: required command '$command' was not found in PATH." >&2
    exit 1
  fi
done

# Rewrites `export NAME="value"` in .env without exposing the value in argv.
set_env() {
  ENV_FILE="$env_file" VAR_NAME="$1" VAR_VALUE="$2" python3 - <<'PY'
import os, re
path, name, value = os.environ["ENV_FILE"], os.environ["VAR_NAME"], os.environ["VAR_VALUE"]
text = open(path).read()
line = f'export {name}="{value}"'
pattern = re.compile(rf'^export {re.escape(name)}=.*$', re.M)
text = pattern.sub(lambda _: line, text, count=1) if pattern.search(text) else text.rstrip("\n") + "\n" + line + "\n"
open(path, "w").write(text)
PY
}

new_client_secret="$(openssl rand -hex 16)"
new_cookie_secret="$(python3 -c 'import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')"

echo "Updating the flagr client secret in the Keycloak database..."
updated="$(docker run --rm -i postgres:14-alpine \
  psql "postgresql://$K3S_DB_USER:$K3S_DB_PASSWORD@$DATABASE_HOST:5432/kc-cluster" \
  -v ON_ERROR_STOP=1 -qtA <<SQL
update client set secret = '$new_client_secret'
 where client_id = 'flagr' and realm_id = (select id from realm where name = 'k8s')
returning 1;
SQL
)"
if [[ "$updated" != "1" ]]; then
  echo "Error: expected to update exactly one client, got '$updated'." >&2
  exit 1
fi

echo "Updating .env..."
set_env OAUTH2_PROXY_CLIENT_SECRET "$new_client_secret"
set_env OAUTH2_PROXY_COOKIE_SECRET "$new_cookie_secret"

echo "Restarting Keycloak so it drops its cached client secret..."
kubectl -n keycloak rollout restart statefulset/keycloak
kubectl -n keycloak rollout status statefulset/keycloak --timeout=600s

echo "Re-applying the oauth2-proxy-secrets Secret..."
"$script_dir/postinstall.sh"
kubectl -n flagr rollout restart deployment/oauth2-proxy
kubectl -n flagr rollout status deployment/oauth2-proxy --timeout=180s

echo "Checking the new client secret against Keycloak (an invalid_grant answer means it was accepted)..."
answer="$(curl -sk -X POST "https://keycloak.home.arpa/realms/k8s/protocol/openid-connect/token" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=flagr" \
  --data-urlencode "client_secret=$new_client_secret" \
  --data-urlencode "code=invalid" \
  --data-urlencode "redirect_uri=https://flagr.home.arpa/oauth2/callback" \
  | python3 -c 'import json, sys; print(json.load(sys.stdin).get("error", "unknown"))')"
echo "Keycloak answered: $answer"

echo "Rotation finished. Log in to https://flagr.home.arpa to confirm the SSO flow."

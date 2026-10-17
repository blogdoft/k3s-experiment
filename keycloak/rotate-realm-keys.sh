#!/usr/bin/env bash
# Rotates the RSA signing (rsa-generated) and encryption (rsa-enc-generated) keys of the k8s and master
# realms through the Keycloak Admin API, then refreshes the recovery files: the KC_*_RSA_* variables in
# .env and the public certificates in keycloak-export/*-realm.json. Secret values are never printed.
# Requires KC_USER and KC_PASS (master realm admin) in .env. Existing sessions and tokens become invalid.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
env_file="$project_dir/.env"
export_dir="$script_dir/keycloak-export"
keycloak_url="${KC_URL:-https://keycloak.home.arpa}"

# shellcheck source=/dev/null
source "$env_file"

for var in KC_USER KC_PASS K3S_DB_USER K3S_DB_PASSWORD DATABASE_HOST; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: $var is not defined in .env." >&2
    exit 1
  fi
done

for command in curl python3 docker; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: required command '$command' was not found in PATH." >&2
    exit 1
  fi
done

kc_curl() {
  curl -fsS --cacert "$project_dir/home-arpa-ca.crt" "$@"
}

# Prints a fresh admin access token (tokens are signed by the master realm keys, so request a new one
# after rotating them).
admin_token() {
  kc_curl -X POST "$keycloak_url/realms/master/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=admin-cli \
    --data-urlencode "username=$KC_USER" --data-urlencode "password=$KC_PASS" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'
}

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

# Lists "<id> <providerId>" of the RSA key providers of a realm.
rsa_providers() {
  kc_curl -H "Authorization: Bearer $1" \
    "$keycloak_url/admin/realms/$2/components?type=org.keycloak.keys.KeyProvider" \
    | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["providerId"] in ("rsa-generated", "rsa-enc-generated"):
        print(c["id"], c["providerId"])'
}

create_provider() {
  local token="$1" realm="$2" realm_id="$3" provider="$4" stamp="$5" algorithm_json=""
  [[ "$provider" == "rsa-enc-generated" ]] && algorithm_json=',"algorithm":["RSA-OAEP"]'
  kc_curl -o /dev/null -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    "$keycloak_url/admin/realms/$realm/components" \
    -d "{\"name\":\"$provider-$stamp\",\"providerId\":\"$provider\",\"providerType\":\"org.keycloak.keys.KeyProvider\",\"parentId\":\"$realm_id\",\"config\":{\"priority\":[\"200\"],\"enabled\":[\"true\"],\"active\":[\"true\"],\"keySize\":[\"2048\"]$algorithm_json}}"
}

rotate_realm() {
  local realm="$1" stamp token realm_id old_ids
  stamp="$(date +%Y%m%d%H%M)"
  token="$(admin_token)"
  realm_id="$(kc_curl -H "Authorization: Bearer $token" "$keycloak_url/admin/realms/$realm" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])')"
  old_ids="$(rsa_providers "$token" "$realm")"

  echo "[$realm] creating new rsa-generated and rsa-enc-generated providers (priority 200)..."
  create_provider "$token" "$realm" "$realm_id" rsa-generated "$stamp"
  create_provider "$token" "$realm" "$realm_id" rsa-enc-generated "$stamp"

  # Delete the old encryption key first and the old signing key last: the admin token of the master
  # realm is signed by the old signing key, so that call must be the final one.
  echo "[$realm] removing the old providers..."
  while read -r id provider; do
    [[ "$provider" == "rsa-enc-generated" ]] && kc_curl -o /dev/null -X DELETE \
      -H "Authorization: Bearer $token" "$keycloak_url/admin/realms/$realm/components/$id"
  done <<<"$old_ids"
  while read -r id provider; do
    [[ "$provider" == "rsa-generated" ]] && kc_curl -o /dev/null -X DELETE \
      -H "Authorization: Bearer $token" "$keycloak_url/admin/realms/$realm/components/$id"
  done <<<"$old_ids"

  token="$(admin_token)"
  active="$(kc_curl -H "Authorization: Bearer $token" "$keycloak_url/admin/realms/$realm/keys" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["active"].get("RS256", "none") != "none")')"
  if [[ "$active" != "True" ]]; then
    echo "Error: realm $realm has no active RS256 key after the rotation." >&2
    exit 1
  fi
  echo "[$realm] done: new RS256 key is active."
}

rotate_realm k8s
rotate_realm master

echo "Refreshing the recovery files from the Keycloak database..."
keys_tsv="$(docker run --rm postgres:14-alpine \
  psql "postgresql://$K3S_DB_USER:$K3S_DB_PASSWORD@$DATABASE_HOST:5432/kc-cluster" \
  -v ON_ERROR_STOP=1 -qtA -F $'\t' -c "
    select r.name, c.provider_id, cc.name, cc.value
      from component_config cc
      join component c on c.id = cc.component_id
      join realm r on r.id = c.realm_id
     where cc.name in ('privateKey', 'certificate')
       and c.provider_id in ('rsa-generated', 'rsa-enc-generated')
       and r.name in ('k8s', 'master')")"

KEYS_TSV="$keys_tsv" EXPORT_DIR="$export_dir" ENV_FILE="$env_file" python3 - <<'PY'
import json, os, re

env_file, export_dir = os.environ["ENV_FILE"], os.environ["EXPORT_DIR"]
variable = {
    ("k8s", "rsa-generated"): "KC_K8S_RSA_PRIVATE_KEY",
    ("k8s", "rsa-enc-generated"): "KC_K8S_RSA_ENC_PRIVATE_KEY",
    ("master", "rsa-generated"): "KC_MASTER_RSA_PRIVATE_KEY",
    ("master", "rsa-enc-generated"): "KC_MASTER_RSA_ENC_PRIVATE_KEY",
}
private, certificate = {}, {}
for row in os.environ["KEYS_TSV"].splitlines():
    realm, provider, name, value = row.split("\t", 3)
    (private if name == "privateKey" else certificate)[(realm, provider)] = value

if set(private) != set(variable) or set(certificate) != set(variable):
    raise SystemExit("Error: expected exactly one key per realm and provider in the database.")

text = open(env_file).read()
for key, name in variable.items():
    pattern = re.compile(rf'^export {name}=.*$', re.M)
    if not pattern.search(text):
        raise SystemExit(f"Error: {name} not found in .env.")
    text = pattern.sub(lambda _: f'export {name}="{private[key]}"', text, count=1)
open(env_file, "w").write(text)

# Swap only the certificate strings in place: re-serializing the JSON would reformat the whole export.
for realm in ("k8s", "master"):
    path = os.path.join(export_dir, f"{realm}-realm.json")
    text = open(path).read()
    for component in json.loads(text)["components"]["org.keycloak.keys.KeyProvider"]:
        key = (realm, component["providerId"])
        if key in certificate:
            old = component["config"]["certificate"][0]
            if text.count(old) != 1:
                raise SystemExit(f"Error: certificate of {key} not found exactly once in {path}.")
            text = text.replace(old, certificate[key])
    open(path, "w").write(text)
PY

echo "Rotation finished. Review 'git diff keycloak/keycloak-export' (only certificates change) and commit."
echo "Argo CD, Flagr and any other SSO session must log in again."

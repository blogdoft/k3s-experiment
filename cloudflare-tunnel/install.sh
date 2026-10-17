#!/usr/bin/env bash

set -euo pipefail

source ../.env

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
env_file="$project_dir/.env"
credentials_file="${CLOUDFLARE_TUNNEL_CREDENTIALS_FILE:-}"

if [[ ! -f "$env_file" ]]; then
  echo "Error: file $env_file not found. Create it from .env.template." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$env_file"

if [[ -z "$credentials_file" || ! -r "$credentials_file" ]]; then
  echo "Error: set CLOUDFLARE_TUNNEL_CREDENTIALS_FILE in .env to a readable credentials.json." >&2
  exit 1
fi

if [[ -z "${CLOUDFLARE_EXTERNAL_DNS_TOKEN:-}" ]]; then
  echo "Error: set CLOUDFLARE_EXTERNAL_DNS_TOKEN in .env (a Zone:DNS:Edit token dedicated to external-dns)." >&2
  exit 1
fi

for command in kubectl envsubst; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: required command '$command' was not found in PATH." >&2
    exit 1
  fi
done

kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -
kubectl -n cloudflare-tunnel create secret generic cloudflared-credentials \
  --from-file=credentials.json="$credentials_file" \
  --dry-run=client -o yaml | kubectl apply -f -

external_dns_secret_template="$script_dir/external-dns-cloudflare-secret.yaml.template"

kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
envsubst '${CLOUDFLARE_EXTERNAL_DNS_TOKEN}' < "$external_dns_secret_template" | kubectl apply -f -

echo "Secret cloudflared-credentials applied to the cloudflare-tunnel namespace."
echo "Secret external-dns-cloudflare applied to the external-dns namespace."
echo "The Deployment is reconciled by Argo CD from k3s-apps."

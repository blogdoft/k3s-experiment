#!/usr/bin/env bash

set -euo pipefail

source ../.env

if [[ -z "${CLOUDFLARE_DNSTOKEN:-}" ]]; then
  echo "Erro: defina CLOUDFLARE_DNSTOKEN antes de executar este script." >&2
  exit 1
fi

for command in kubectl envsubst; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Erro: o comando necessário '$command' não foi encontrado no PATH." >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
secret_template="$script_dir/cloudflare-dns-api-token-secret.yaml.template"

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
envsubst '${CLOUDFLARE_DNSTOKEN}' < "$secret_template" | kubectl apply -f -

echo "Namespace cert-manager e Secret cloudflare-dns-api-token aplicados."

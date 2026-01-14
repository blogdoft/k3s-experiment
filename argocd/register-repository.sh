#!/usr/bin/env bash
set -euo pipefail

# Registers the k3s-apps repository in ArgoCD using ArgoCD CLI
# with SSH private key authentication.
#
# This avoids committing private keys into the repo.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="git@github.com:blogdoft/k3s-apps.git"

# Check if argocd CLI is available
if ! command -v argocd &> /dev/null; then
  echo "ArgoCD CLI (argocd) não encontrado. Instale-o primeiro:" >&2
  echo "  https://argo-cd.readthedocs.io/en/stable/cli_installation/" >&2
  exit 2
fi

read -r -p "Caminho da chave privada SSH (ex: /home/ftathiago/.ssh/id_ed25519-github): " KEY_PATH
if [[ -z "${KEY_PATH}" ]]; then
  echo "Caminho vazio." >&2
  exit 2
fi

# Expand ~ manually (bash doesn't expand inside quotes)
if [[ "$KEY_PATH" == ~/* ]]; then
  KEY_PATH="$HOME/${KEY_PATH#~/}"
fi

echo "Usando chave: $KEY_PATH"

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Arquivo não encontrado: $KEY_PATH" >&2
  exit 2
fi

# Register repository using ArgoCD CLI
echo "Registrando repositório $REPO_URL no ArgoCD..."
if argocd repo add "$REPO_URL" --grpc-web --insecure --ssh-private-key-path "$KEY_PATH"; then
  echo "✓ Repositório registrado com sucesso!"
  echo ""
  echo "Para verificar:"
  echo "  argocd repo list --grpc-web --insecure"
else
  echo "✗ Falha ao registrar repositório" >&2
  exit 1
fi

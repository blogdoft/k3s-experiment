#!/usr/bin/env bash
set -euo pipefail

# Generates a copy of `argocd/repo-secret.yaml` with `stringData.sshPrivateKey` filled
# from a local SSH private key file.
#
# This avoids committing private keys into the repo.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/repo-secret.yaml"
DEFAULT_OUT_FILE="$SCRIPT_DIR/repo-secret.generated.yaml"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Template not found: $TEMPLATE_FILE" >&2
  exit 2
fi

read -r -p "Caminho da chave privada SSH (ex: ~/.ssh/id_ed25519): " KEY_PATH
if [[ -z "${KEY_PATH}" ]]; then
  echo "Caminho vazio." >&2
  exit 2
fi

# Expand ~ manually (bash doesn't expand inside quotes)
if [[ "$KEY_PATH" == ~/* ]]; then
  KEY_PATH="$HOME/${KEY_PATH#~/}"
fi

echo $KEY_PATH

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Arquivo não encontrado: $KEY_PATH" >&2
  exit 2
fi

read -r -p "Arquivo de saída [${DEFAULT_OUT_FILE}]: " OUT_FILE
OUT_FILE="${OUT_FILE:-$DEFAULT_OUT_FILE}"

# Ensure output directory exists
OUT_DIR="$(dirname -- "$OUT_FILE")"
mkdir -p "$OUT_DIR"

awk -v keyfile="$KEY_PATH" '
  BEGIN { in_key_block = 0 }
  /^  sshPrivateKey: \|[[:space:]]*$/ {
    print
    while ((getline line < keyfile) > 0) {
      sub(/\r$/, "", line) # handle CRLF
      print "    " line
    }
    close(keyfile)
    in_key_block = 1
    next
  }
  in_key_block {
    # Skip existing sshPrivateKey block lines (they are indented by 4+ spaces).
    # Stop skipping when indentation drops back.
    if ($0 ~ /^    /) {
      next
    }
    in_key_block = 0
  }
  { print }
' "$TEMPLATE_FILE" > "$OUT_FILE"

chmod 600 "$OUT_FILE" 2>/dev/null || true

echo "Gerado: $OUT_FILE"

echo "Aplicar no cluster (exemplo):"
echo "  kubectl apply -f $OUT_FILE"

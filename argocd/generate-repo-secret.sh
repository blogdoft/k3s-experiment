#!/usr/bin/env bash
set -euo pipefail

source ../.env

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/argocd-secret.yaml"
OUTPUT_FILE="$SCRIPT_DIR/argocd-secret.generated.yaml"

envsubst < "$SOURCE_FILE" > "$OUTPUT_FILE"

kubectl apply -f $OUTPUT_FILE -n argocd 

rm $OUTPUT_FILE

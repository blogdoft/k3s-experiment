#!/bin/bash

set -e

echo "Applying Flagr secrets..."

kubectl create namespace flagr --dry-run=client -o yaml | kubectl apply -f - 

kubectl -n flagr create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER="$K3S_DB_USER" \
  --from-literal=POSTGRES_PASSWORD="$K3S_DB_PASSWORD" \
  --from-literal=POSTGRES_HOST="192.168.1.212" \
  --from-literal=POSTGRES_PORT="5432" \
  --from-literal=POSTGRES_DB="flagr" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

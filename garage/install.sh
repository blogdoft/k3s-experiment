#!/usr/bin/env bash

set -euo pipefail

kubectl create namespace garage --dry-run=client -o yaml | kubectl apply -f -

# Secrets are generated randomly and only created when missing, so re-running
# the installation does not rotate values that Garage already uses.
if kubectl -n garage get secret garage-rpc >/dev/null 2>&1; then
  echo "Secret garage-rpc already exists, keeping it"
else
  kubectl create secret generic garage-rpc -n garage \
    --from-literal=rpcSecret="$(openssl rand -hex 32)"
fi

if kubectl -n garage get secret garage-admin >/dev/null 2>&1; then
  echo "Secret garage-admin already exists, keeping it"
else
  kubectl create secret generic garage-admin -n garage \
    --from-literal=admin-token="$(openssl rand -base64 32)"
fi

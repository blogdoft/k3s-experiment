#!/usr/bin/env bash

set -euo pipefail

source ../.env

kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic oauth2-proxy-secrets -n longhorn-system \
  --from-literal=client-secret=$KC_LONGHORN_CLIENT_SECRET \
  --from-literal=cookie-secret=$LONGHORN_OAUTH2_COOKIE_SECRET --dry-run=client -o yaml | kubectl apply -f -

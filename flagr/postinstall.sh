#!/bin/bash

set -e

source ../.env

echo "Configuring Flagr/oauth2 secrets"

kubectl -n flagr create secret generic oauth2-proxy-secrets \
  --from-literal=OAUTH2_PROXY_CLIENT_ID="flagr" \
  --from-literal=OAUTH2_PROXY_CLIENT_SECRET="$(docker run --rm postgres:14-alpine \
    psql "postgresql://$K3S_DB_USER:$K3S_DB_PASSWORD@$DATABASE_HOST:5432/kc-cluster" \
    -tA -c "select secret from client where client_id = 'flagr'")" \
  --from-literal=OAUTH2_PROXY_COOKIE_SECRET="$OAUTH2_PROXY_COOKIE_SECRET" \
  --save-config \
  --dry-run=client -o yaml  | kubectl apply -f -

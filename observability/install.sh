#!/usr/bin/env bash

set -euo pipefail

source ../.env

kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic grafana-admin -n observability \
  --from-literal=admin-user=$ANSIBLE_MORGUL \
  --from-literal=admin-password=$ANSIBLE_PASSWORD --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic grafana-oidc -n observability \
  --from-literal=client-secret=$KC_GRAFANA_CLIENT_SECRET --dry-run=client -o yaml | kubectl apply -f -

envsubst < grafana-contactpoints-secret.yaml | kubectl apply -f -

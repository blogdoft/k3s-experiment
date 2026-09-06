#!/usr/bin/env bash

set -euo pipefail

source ../.env

kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic grafana-admin -n observability \
  --from-literal=admin-user=$ANSIBLE_MORGUL \
  --from-literal=admin-password=$ANSIBLE_PASSWORD
#!/usr/bin/env bash

set -euo pipefail

source ../.env

kubectl create namespace kafka-ui --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic kafka-ui-oidc -n kafka-ui \
  --from-literal=client-secret=$KC_KAFKA_UI_CLIENT_SECRET --dry-run=client -o yaml | kubectl apply -f -

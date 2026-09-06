#!/usr/bin/env bash

set -euo pipefail

source ../.env

kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic minio-credentials -n minio \
  --from-literal=root-user=$ANSIBLE_MORGUL \
  --from-literal=root-password=$ANSIBLE_PASSWORD
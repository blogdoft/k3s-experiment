#!/usr/bin/env bash

set -euo pipefail
set +x

. ../.env

set +e
echo "Apagando deployment anterior"
kubectl delete deploy/forgejo-runner -n forgejo > /dev/null
kubectl delete deploy/forgejo-runner-host -n forgejo > /dev/null
set -e

PACKAGE_FILE=forgejo-cli-x86_64-linux.tar.gz
TEMPLATE_FILE_DOCKER=runner.yaml
TEMP_FILE_DOCKER=runner-temp.yaml

TEMPLATE_FILE_HOST=runner-host.yaml
TEMP_FILE_HOST=runner-host-temp.yaml

export RUNNER_TOKEN=$(kubectl exec -n forgejo deploy/forgejo -- su git -c "forgejo actions grt")

echo "Token encontrado:" $RUNNER_TOKEN

envsubst < "$TEMPLATE_FILE_DOCKER" > "$TEMP_FILE_DOCKER"
envsubst < "$TEMPLATE_FILE_HOST" > "$TEMP_FILE_HOST"

kubectl apply -f $TEMP_FILE_DOCKER -n forgejo
kubectl apply -f $TEMP_FILE_HOST -n forgejo

rm $TEMP_FILE_DOCKER
rm $TEMP_FILE_HOST

kubectl rollout restart deployment forgejo-runner -n forgejo
kubectl rollout restart deployment forgejo-runner-host -n forgejo

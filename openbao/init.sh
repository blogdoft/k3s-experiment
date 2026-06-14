#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="openbao"
POD_NAME="${POD_NAME:-openbao-0}"

INIT_FILE="openbao-init.json"
UNSEAL_FILE="openbao-unseal-keys.txt"
TOKEN_FILE="openbao-root-token.txt"

confirm() {
  local answer
  read -r -p "$1 (y/yes to confirm): " answer
  [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]
}

echo "Checking pod: ${POD_NAME}"

if ! kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" >/dev/null 2>&1; then
  echo "Pod ${POD_NAME} was not found in namespace ${NAMESPACE}"
  exit 1
fi

CONTAINER_NAME=$(kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" \
  -o jsonpath='{.spec.containers[0].name}')

if [ -z "${CONTAINER_NAME}" ]; then
  echo "No container found in pod ${POD_NAME}"
  exit 1
fi

echo "Container found: ${CONTAINER_NAME}"

if confirm "Do you want to initialize OpenBao?"; then
  echo "Initializing OpenBao..."

  kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" -- \
    bao operator init -format=json > "${INIT_FILE}"

  echo "Extracting initialization data..."

  jq -r '.root_token' "${INIT_FILE}" > "${TOKEN_FILE}"
  jq -r '.unseal_keys_b64[]' "${INIT_FILE}" > "${UNSEAL_FILE}"

  chmod 600 "${INIT_FILE}" "${UNSEAL_FILE}" "${TOKEN_FILE}"

  echo "Files generated:"
  echo "  - ${INIT_FILE}"
  echo "  - ${UNSEAL_FILE}"
  echo "  - ${TOKEN_FILE}"
  echo
fi

if confirm "Do you want to unseal OpenBao?"; then
  if [ ! -f "${UNSEAL_FILE}" ]; then
    echo "File not found: ${UNSEAL_FILE}"
    exit 1
  fi

  echo "Starting unseal process..."

  head -n 3 "${UNSEAL_FILE}" | while read -r KEY; do
    echo "Applying unseal key..."
    kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" -- \
      bao operator unseal "${KEY}"
  done

  echo
  echo "Final status:"

  kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" -- \
    bao status

  echo
  echo "OpenBao successfully unsealed."
fi
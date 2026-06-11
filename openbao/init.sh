#!/usr/bin/env sh

set -e

NAMESPACE="openbao"
POD_NAME="${POD_NAME:-openbao-0}"

INIT_FILE="openbao-init.json"
UNSEAL_FILE="openbao-unseal-keys.txt"
TOKEN_FILE="openbao-root-token.txt"

echo "Verificando pod: ${POD_NAME}"

if ! kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" >/dev/null 2>&1; then
  echo "Pod ${POD_NAME} não encontrado no namespace ${NAMESPACE}"
  exit 1
fi

CONTAINER_NAME=$(kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" \
  -o jsonpath='{.spec.containers[0].name}')

if [ -z "${CONTAINER_NAME}" ]; then
  echo "Nenhum container encontrado no pod ${POD_NAME}"
  exit 1 
fi

echo "Container encontrado: ${CONTAINER_NAME}"

echo "Inicializando OpenBao..."

kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" -- \
  bao operator init -format=json > "${INIT_FILE}"

echo "Extraindo arquivos locais..."

jq -r '.root_token' "${INIT_FILE}" > "${TOKEN_FILE}"
jq -r '.unseal_keys_b64[]' "${INIT_FILE}" > "${UNSEAL_FILE}"

chmod 600 "${INIT_FILE}" "${UNSEAL_FILE}" "${TOKEN_FILE}"

echo "Arquivos gerados localmente:"
echo "  - ${INIT_FILE}"
echo "  - ${UNSEAL_FILE}"
echo "  - ${TOKEN_FILE}"

echo ""
echo "Executando unseal..."

head -n 3 "${UNSEAL_FILE}" | while read -r KEY; do
  echo "Aplicando unseal key..."
  kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" -- \
    bao operator unseal "${KEY}"
done

echo ""
echo "Status final:"

kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" -- \
  bao status

echo ""
echo "OpenBao inicializado e desbloqueado com sucesso."
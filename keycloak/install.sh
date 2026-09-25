#!/bin/bash

source ../.env

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Processing export files..."-e

REQUIRED_VARS=(
  OAUTH2_PROXY_CLIENT_SECRET KC_ARGOCD_CLIENT_SECRET
  KC_K8S_HMAC_SECRET KC_K8S_AES_SECRET KC_K8S_RSA_PRIVATE_KEY KC_K8S_RSA_ENC_PRIVATE_KEY
  KC_MASTER_HMAC_SECRET KC_MASTER_AES_SECRET KC_MASTER_RSA_PRIVATE_KEY KC_MASTER_RSA_ENC_PRIVATE_KEY
)

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: Variable $var is not defined"
    echo "Run: export $var='your-secret'"
    echo "Or: source .env"
    exit 1
  fi
done

echo "✓ Realm import variables found"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Processing export files..."

for file in keycloak-export/*.json; do
  filename=$(basename "$file")
  echo "  → $filename"
  envsubst < "$file" > "$TEMP_DIR/$filename"
done

echo "Creating ConfigMap in keycloak namespace..."

kubectl create namespace keycloak \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n keycloak create configmap keycloak-realm-import \
    --save-config \
    --from-file="$TEMP_DIR" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Creating database secret in keycloak namespace..."

kubectl -n keycloak create secret generic keycloak-database-secret \
  --from-literal=KC_DB_USERNAME="$K3S_DB_USER" \
  --from-literal=KC_DB_PASSWORD="$K3S_DB_PASSWORD" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ ConfigMap keycloak-realm-import successfully created/updated!"
echo ""
echo "To verify:"
echo "  kubectl -n keycloak get configmap keycloak-realm-import"
echo "  kubectl -n keycloak describe secret keycloak-database-secret"
echo "  kubectl -n keycloak describe configmap keycloak-realm-import"

#!/usr/bin/env bash

set -euo pipefail
set +x

. ../.env

read -r -p  "Do you want to build host runner image? (y/yes to confirm): " build_image
if [[ "$build_image" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "You must have completed forgejo installation and configured the secrets before building the host runner image."
    echo "Access https://forgejo.home.arpa before continue"
    read -p "Press Enter to continue..."
    # ============================================================
    # Validation
    # ============================================================

    export REGISTRY_USERNAME=""
    export REGISTRY_PASSWORD=""

    read -r -p "Enter your forgejo username: " REGISTRY_USERNAME
    read -r -sp "Enter your forgejo password: " REGISTRY_PASSWORD
    echo

    REGISTRY="forgejo.home.arpa"
    OWNER=$REGISTRY_USERNAME
    IMAGE_NAME="forgejo-runner-custom"
    IMAGE_TAG="13"

    FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE_NAME}:${IMAGE_TAG}"

    BUILDER_NAME="forgejo-builder"

    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    CA_FILE="$(realpath "${SCRIPT_DIR}/../home-arpa-ca.crt")"
    BUILDKIT_CONFIG_DIR="${HOME}/.config/buildkit"
    BUILDKIT_CONFIG="${BUILDKIT_CONFIG_DIR}/buildkitd.toml"

    if [[ ! -f "${CA_FILE}" ]]; then
        echo "ERROR: CA certificate not found:"
        echo "  ${CA_FILE}"
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: docker CLI is not installed."
        exit 1
    fi

    if ! docker buildx version >/dev/null 2>&1; then
        echo "ERROR: Docker Buildx is not installed."
        echo "Install the docker-buildx-plugin package first."
        exit 1
    fi

    if [[ -z "${REGISTRY_USERNAME:-}" ]]; then
        echo "ERROR: REGISTRY_USERNAME is not defined."
        exit 1
    fi

    if [[ -z "${REGISTRY_PASSWORD:-}" ]]; then
        echo "ERROR: REGISTRY_PASSWORD is not defined."
        exit 1
    fi

    if [[ ! -f "./Dockerfile" ]]; then
        echo "ERROR: Dockerfile was not found in the current directory."
        exit 1
    fi

    # ============================================================
    # Authenticate against Forgejo Container Registry
    # ============================================================

    echo "Logging into ${REGISTRY}..."

    echo "${REGISTRY_PASSWORD}" |
    docker login "${REGISTRY}" \
        --username "${REGISTRY_USERNAME}" \
        --password-stdin

    echo "Registry login successful."

    # ------------------------------------------------------------
    # Create BuildKit configuration
    # ------------------------------------------------------------

    mkdir -p "${BUILDKIT_CONFIG_DIR}"

    cat > "${BUILDKIT_CONFIG}" <<EOF
debug = true

[registry."${REGISTRY}"]
ca = ["${CA_FILE}"]
EOF
    docker buildx rm "${BUILDER_NAME}" 2>/dev/null || true

    docker buildx create \
        --name "${BUILDER_NAME}" \
        --driver docker-container \
        --buildkitd-config "${BUILDKIT_CONFIG}" \
        --use

    docker buildx inspect \
        "${BUILDER_NAME}" \
        --bootstrap

    docker buildx build \
        --builder "${BUILDER_NAME}" \
        --platform linux/amd64 \
        --tag "${FULL_IMAGE}" \
        --push \
        .

    docker buildx imagetools inspect "${FULL_IMAGE}"
    echo
    echo
    echo "Docker image for forgejo-runner built and pushed successfully!"
    echo "Image: ${FULL_IMAGE}"
fi
echo "#####################################################################################"
echo


set +e
echo "Delete any old forgejo-runner deployments"
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

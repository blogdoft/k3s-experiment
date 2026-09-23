#!/usr/bin/env bash

set -euo pipefail
set +x

. ../.env

# ============================================================
# Image reference (always needed, even on redeploy without rebuild,
# so runner-host.yaml's ${FULL_IMAGE} placeholder can be resolved)
# ============================================================

REGISTRY="forgejo.home.arpa"
IMAGE_NAME="forgejo-runner-custom"
IMAGE_TAG="13"

export REGISTRY_USERNAME=""

read -r -p "Enter your forgejo username (image owner/namespace): " REGISTRY_USERNAME
OWNER="$REGISTRY_USERNAME"

export FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE_NAME}:${IMAGE_TAG}"

read -r -p  "Do you want to build host runner image? (y/yes to confirm): " build_image
if [[ "$build_image" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "You must have completed forgejo installation and configured the secrets before building the host runner image."
    echo "Access https://forgejo.home.arpa before continue"
    read -p "Press Enter to continue..."
    # ============================================================
    # Validation
    # ============================================================

    export REGISTRY_PASSWORD=""

    read -r -sp "Enter your forgejo password: " REGISTRY_PASSWORD
    echo

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

    # The CA needs to be inside the build context so the Dockerfile can
    # trust it (job containers run "host" backend jobs, i.e. git/https
    # calls made directly from this image against forgejo.home.arpa).
    cp "${CA_FILE}" "./home-arpa-ca.crt"

    docker buildx build \
        --builder "${BUILDER_NAME}" \
        --platform linux/amd64 \
        --tag "${FULL_IMAGE}" \
        --push \
        .

    rm -f "./home-arpa-ca.crt"

    docker buildx imagetools inspect "${FULL_IMAGE}"
    echo
    echo
    echo "Docker image for forgejo-runner built and pushed successfully!"
    echo "Image: ${FULL_IMAGE}"
fi
echo "#####################################################################################"
echo

REGISTRY_MIRROR_FILE=registry-mirror.yaml

echo "Applying Docker Hub pull-through registry mirror (idempotent, no delete)..."
kubectl apply -f "$REGISTRY_MIRROR_FILE" -n forgejo
kubectl rollout status deployment/docker-registry-mirror -n forgejo --timeout=120s
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

# Only substitute the placeholders these templates actually define ($RUNNER_TOKEN,
# ${FULL_IMAGE}). Without this allowlist, envsubst also matches bare $vars used by
# the bash startup script embedded in each manifest (e.g. $child, $RANDOM), which
# aren't set in this shell and get silently replaced with an empty string, corrupting
# the deployed script (e.g. "wait \"\$child\"" becomes "wait \"\"", which never blocks
# on the runner process and leaks one orphaned forgejo-runner process per loop cycle).
envsubst '$RUNNER_TOKEN' < "$TEMPLATE_FILE_DOCKER" > "$TEMP_FILE_DOCKER"
envsubst '$RUNNER_TOKEN ${FULL_IMAGE}' < "$TEMPLATE_FILE_HOST" > "$TEMP_FILE_HOST"

kubectl apply -f $TEMP_FILE_DOCKER -n forgejo
kubectl apply -f $TEMP_FILE_HOST -n forgejo

rm $TEMP_FILE_DOCKER
rm $TEMP_FILE_HOST

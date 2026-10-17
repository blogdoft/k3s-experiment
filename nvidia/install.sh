#!/bin/bash

CURRENT_DIR=$(pwd)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

cd ${SCRIPT_DIR}

set -e

source ../.env

CHART_VERSION=0.20.1
NAMESPACE=nvidia-device-plugin
GPU_NODE=${HOST_NAME:-morgul}

echo "Checking RuntimeClass nvidia (created by k3s when nvidia-container-runtime is on the host)"
kubectl get runtimeclass nvidia > /dev/null

echo "Labeling node ${GPU_NODE} so the device plugin is scheduled on it (no NFD in the cluster)"
kubectl label node "${GPU_NODE}" nvidia.com/gpu.present=true --overwrite

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update nvdp

echo "Installing NVIDIA device plugin ${CHART_VERSION} (time-slicing, 4 replicas per GPU)"
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --version "${CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values values.yaml \
  --wait

echo "Waiting for ${GPU_NODE} to advertise nvidia.com/gpu"
for _ in $(seq 1 30); do
  GPUS=$(kubectl get node "${GPU_NODE}" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')
  [ -n "${GPUS}" ] && break
  sleep 2
done

echo "nvidia.com/gpu allocatable on ${GPU_NODE}: ${GPUS:-none}"
[ -n "${GPUS}" ] || { echo "GPU was not advertised, check: kubectl -n ${NAMESPACE} logs ds/nvidia-device-plugin"; exit 1; }

cd $CURRENT_DIR

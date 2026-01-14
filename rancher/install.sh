#!/bin/bash

set -e

echo "Waiting until deploy/rancher and deploy/rancher-webhook are available..."
kubectl -n cattle-system wait --for=condition=Available deploy/rancher deploy/rancher-webhook --timeout=10m

kubectl label node morgul rancher-node=primary

kubectl -n cattle-system patch deploy rancher-webhook \
  -p '{
    "spec": {
      "template": {
        "spec": {
          "nodeSelector": {
            "rancher-node": "primary"
          }
        }
      }
    }
  }'

kubectl -n cattle-system patch deploy rancher \
  -p '{
    "spec": {
      "template": {
        "spec": {
          "nodeSelector": {
            "rancher-node": "primary"
          }
        }
      }
    }
  }'

kubectl -n cattle-system rollout status deploy/rancher
  
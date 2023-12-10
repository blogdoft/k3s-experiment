#!/bin/bash

kubectl apply -f 01-pvc.yaml
kubectl apply -f 04-service.yaml

helm upgrade --install postgres-container bitnami/postgresql --set persistence.existingClaim=postgres-pvc --set volumePermissions.enabled=true --namespace postgres-server
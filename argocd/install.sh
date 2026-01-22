#!/bin/bash

set -e

# This will install the ArgoCD manifest, and add and ingress for traefik so you can access it on http://hostname/argocd
kubectl create namespace argocd \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl apply -f - << "EOF"
---
#Need to configure argocd to server.insecure: "true"
#https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#traefik-v22
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cmd-params-cm
    app.kubernetes.io/part-of: argocd
data:
  server.insecure: "true"
  # Removed server.basehref and server.rootpath to serve from root
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  rules:
  - host: argocd.home.arpa
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: argocd-server
            port:
              name: http
EOF

kubectl -n argocd patch secret argocd-secret --patch='{"stringData": { "oidc.keycloak.clientSecret": "'"$ARGOCD_KC_CLIENT_SECRET"'" }}'

#now redeploy and wait
kubectl -n argocd rollout restart deploy argocd-server
#wait for pod to come up
kubectl wait pods --timeout=120s --for=condition=Ready -n argocd -l app.kubernetes.io/name=argocd-server

echo "      ##########################################"
echo "      ##  Waiting for Ingress to be ready    ##"
echo "      ##########################################"

# Wait for Ingress to be created
echo "Checking if Ingress argocd-ingress was created..."
until kubectl get ingress argocd-ingress -n argocd &>/dev/null; do
  echo "Waiting for Ingress to be created..."
  sleep 2
done
echo "✓ Ingress created"

# Wait for Traefik to process the Ingress (checking connectivity)
echo "Checking connectivity at https://argocd.home.arpa ..."
max_attempts=30
attempt=0
until curl -k -s -f -o /dev/null https://argocd.home.arpa || [ $attempt -eq $max_attempts ]; do
  echo "Waiting for ArgoCD to respond via Ingress (attempt $((attempt+1))/$max_attempts)..."
  sleep 5
  attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
  echo "⚠️  WARNING: Timeout waiting for Ingress to respond. Trying login anyway..."
else
  echo "✓ ArgoCD accessible via Ingress"
fi

echo "      ##########################################"
echo "      ##  Logging into ArgoCD                ##"
echo "      ##########################################"
argocd login argocd.home.arpa \
    --grpc-web \
    --insecure \
    --username admin \
    --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "      ##########################################"
echo "      ##  Registering app repository         ##"
echo "      ##########################################"

./register-repository.sh

kubectl apply -f https://raw.githubusercontent.com/blogdoft/k3s-apps/refs/heads/main/bootstrap/root-app.yaml

echo "      ##########################################"
echo "      ##  Waiting for apps to sync           ##"
echo "      ##########################################"

# Check if still logged into ArgoCD
echo "Checking ArgoCD login..."
if ! argocd account get-user-info --grpc-web --insecure &>/dev/null; then
  echo "Logging into ArgoCD again..."
  argocd login argocd.home.arpa --grpc-web --insecure \
      --username admin \
      --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
fi

# Wait a moment for the application to be processed
echo "Waiting for application to be processed..."
sleep 10

echo "      ##########################################"
echo "      ##  Waiting for resources to be ready  ##"
echo "      ##########################################"

# Function to wait for deployments to be ready
wait_for_deployments() {
    local namespace=$1
    local timeout=${2:-300}
    
    echo "Checking deployments in namespace ${namespace}..."
    
    # List all deployments in the namespace
    local deployments=$(kubectl get deployments -n "${namespace}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$deployments" ]; then
        echo "  ✓ No deployments found in ${namespace}"
        return 0
    fi
    
    for deploy in $deployments; do
        echo "  → Waiting for deployment/${deploy} in ${namespace}..."
        if kubectl wait --for=condition=Available --timeout="${timeout}s" \
            "deployment/${deploy}" -n "${namespace}" 2>/dev/null; then
            echo "  ✓ deployment/${deploy} is ready"
        else
            echo "  ⚠️  deployment/${deploy} did not become ready within timeout"
        fi
    done
}

# Function to wait for statefulsets to be ready
wait_for_statefulsets() {
    local namespace=$1
    local timeout=${2:-300}
    
    echo "Checking statefulsets in namespace ${namespace}..."
    
    # List all statefulsets in the namespace
    local statefulsets=$(kubectl get statefulsets -n "${namespace}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$statefulsets" ]; then
        echo "  ✓ No statefulsets found in ${namespace}"
        return 0
    fi
    
    for sts in $statefulsets; do
        echo "  → Waiting for statefulset/${sts} in ${namespace}..."
        
        local elapsed=0
        local ready=false
        
        while [ $elapsed -lt $timeout ]; do
            # Get replicas and readyReplicas
            local replicas=$(kubectl get statefulset "${sts}" -n "${namespace}" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
            local ready_replicas=$(kubectl get statefulset "${sts}" -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            
            # Check if all replicas are ready
            if [ "$replicas" != "0" ] && [ "$replicas" == "$ready_replicas" ]; then
                echo "  ✓ statefulset/${sts} is ready (${ready_replicas}/${replicas})"
                ready=true
                break
            fi
            
            if [ $((elapsed % 15)) -eq 0 ]; then
                echo "    Waiting... (${ready_replicas}/${replicas} ready, ${elapsed}s/${timeout}s)"
            fi
            
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        if [ "$ready" != "true" ]; then
            echo "  ⚠️  statefulset/${sts} did not become ready within timeout"
        fi
    done
}

# Wait for ArgoCD applications to be created
echo "Waiting for ArgoCD applications to be created..."
max_wait=60
elapsed=0
while [ $elapsed -lt $max_wait ]; do
    app_count=$(argocd app list -o name --grpc-web 2>/dev/null | wc -l)
    if [ "$app_count" -gt 0 ]; then
        echo "✓ Found ${app_count} ArgoCD applications"
        break
    fi
    echo "Waiting for applications to be created... (${elapsed}s/${max_wait}s)"
    sleep 5
    elapsed=$((elapsed + 5))
done

# Get all namespaces managed by ArgoCD (except openbao)
echo "Getting namespaces from ArgoCD applications..."
argocd_namespaces=$(argocd app list --grpc-web -o json 2>/dev/null | \
    jq -r '.[] | select(.metadata.name | contains("openbao") | not) | .spec.destination.namespace' | \
    sort -u | grep -v '^$' || echo "")

# If unable to get via ArgoCD, use common namespaces
if [ -z "$argocd_namespaces" ]; then
    echo "⚠️  Could not get namespaces via ArgoCD, using default list..."
    argocd_namespaces="argocd traefik metallb-system cert-manager vault redis keycloak"
fi
sleep 30 

# Wait for resources in each namespace (except openbao)
for ns in $argocd_namespaces; do
    # Check if namespace exists
    if ! kubectl get namespace "${ns}" &>/dev/null; then
        echo "⏭️  Namespace ${ns} does not exist yet, skipping..."
        continue
    fi
    
    if [[ "${ns}" == *"openbao"* ]]; then
        echo "⏭️  Skipping namespace ${ns} (configured to ignore)"
        continue
    fi
    
    echo ""
    echo "📦 Namespace: ${ns}"
    wait_for_deployments "${ns}" 300
    wait_for_statefulsets "${ns}" 300
done

echo ""
echo "✓ Resource verification completed!"

# List final status of applications
echo "Final status of applications:"
argocd app list --grpc-web --insecure

defaultPass=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
echo "##### DEFAULT PASSWORD FOR ADMIN IS $defaultPass #####"

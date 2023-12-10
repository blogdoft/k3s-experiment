#!/bin/bash

ansible-playbook 03-install-agent.yaml -i ./inventory/01-inventory.yaml

kubectl label nodes worker1 kubernetes.io/role=worker
kubectl label nodes worker2 kubernetes.io/role=worker
kubectl label nodes worker1 node-type=worker
kubectl label nodes worker2 node-type=worker

# # ## Install ingress
echo
echo "Instalando o Ingress"
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=200s

echo
echo "Reiniciando o cluster"
ansible-playbook 00-rebootAll.yaml -i ./inventory/01-inventory.yaml

# Teste Ingress
echo
echo "Teste Ingress"
kubectl create deployment demo --image=httpd --port=80
kubectl expose deployment demo
kubectl create ingress demo-localhost --class=nginx \
  --rule="demo.localdev.me/*=demo:80"

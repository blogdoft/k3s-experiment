#!/bin/bash

set -e
source ../.env
cp _wildcard.home.arpa+1-key.pem ./ansible/files/wildcard.home.arpa.key
cp _wildcard.home.arpa+1.pem ./ansible/files/wildcard.home.arpa.crt

# Copia certificados para os demais nós
set +e
ansible-playbook ./ansible/playbook.yaml -i ../inventory.yaml
ansible_rc=$?
set -e
if [ $ansible_rc -ne 0 ]; then
    echo "WARN: ansible-playbook falhou (rc=$ansible_rc). Continuando a execução..." >&2
fi
sudo cp ./ansible/files/wildcard.home.arpa.crt /usr/local/share/ca-certificates/ -r
sudo update-ca-certificates -f

kubectl create secret tls wildcard-home-arpa --namespace=kube-system \
    --key=_wildcard.home.arpa+1-key.pem \
    --cert=_wildcard.home.arpa+1.pem \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls traefik-tls-cert --namespace=kube-system \
    --key=_wildcard.home.arpa+1-key.pem \
    --cert=_wildcard.home.arpa+1.pem \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls traefik-default-cert --namespace=kube-system \
    --key=_wildcard.home.arpa+1-key.pem \
    --cert=_wildcard.home.arpa+1.pem \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls traefik-default-cert --namespace=kube-system  \
    --cert=_wildcard.home.arpa+1.pem \
    --key=_wildcard.home.arpa+1-key.pem \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -

#!/bin/bash

kubectl apply -f pvc.yaml
sudo apt install openssl
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout registry.key -out registry.crt -subj "/CN=registry.cube.local" -addext "subjectAltName=DNS:registry.cube.local,DNS:*.cube.local,IP:192.168.1.145"
kubectl create secret tls docker-registry-tls-cert -n docker-registry --cert=registry.crt --key=registry.key
kubectl apply -f deploy.yaml
kubectl wait --namespace docker-registry --for=condition=ready pod --all 

ansible all -b -m copy -a "src=registry.crt dest=/usr/local/share/ca-certificates/registry.crt" -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml
ansible all -b -m copy -a "src=registry.key dest=/usr/local/share/ca-certificates/registry.key" -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml
ansible all -b -m shell -a "update-ca-certificates" -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml
sudo cp registry.* /usr/local/share/ca-certificates/ -r
sudo update-ca-certificates
ansible-playbook ./ansible/update-hosts.yaml -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml
ansible all -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml -b -m file -a "path=/etc/rancher/k3s state=directory"
ansible all -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml -b -m copy -a "src=./registries.yaml dest=/etc/rancher/k3s/registries.yaml"
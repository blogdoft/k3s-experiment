#!/bin/bash

ansible-playbook 01-update-server.yaml -i ./inventory/01-inventory.yaml
ansible-playbook 00-rebootAll.yaml -i ./inventory/01-inventory.yaml 
ansible-playbook 02-install-controller.yaml -i ./inventory/01-inventory.yaml

# Copy kubeconfig pra máquina local
echo 
echo "Preparando ambiente para uso do Lens"
scp ftathiago@192.168.1.145:~/.kube/config ~/.kube/config
# "3de8d193-4c17-4751-b35b-94bb465fbd98" é o nome do arquivo que contem o kubeconfig do cluster no lens
cp ~/.kube/config /mnt/c/Users/ftath/AppData/Roaming/OpenLens/kubeconfigs/3de8d193-4c17-4751-b35b-94bb465fbd98 

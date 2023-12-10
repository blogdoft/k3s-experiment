#!/bin/bash

kubectl create namespace redis-server

# ## Apply PVC
kubectl apply -f pvc.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/redis-pvc -n redis-server
echo "PVC Bound" && sleep 1; 
kubectl get pvc redis-pvc -n redis-server

## Apply Deployment

kubectl apply -f deployment.yaml
kubectl rollout restart deployment redis-server -n redis-server
kubectl rollout status deployment redis-server -n redis-server --timeout=180s

## Apply Service
kubectl apply -f service.yaml

## Defina a linha que você deseja verificar e adicionar
linha="192.168.1.145   redis   redis.local.dev"

echo Update "/etc/hosts" local
if grep -qF "$linha" /etc/hosts; then
    echo "A linha já está presente no arquivo."
else
    # Adicione a linha ao final do arquivo
    echo "$linha" | sudo tee -a /etc/hosts > /dev/null
    echo "Linha adicionada ao arquivo."
fi

echo Update Windows hosts
if grep -qF "$linha" /mnt/c/Windows/System32/drivers/etc/hosts; then
    echo "A linha já está presente no arquivo."
else
    # Adicione a linha ao final do arquivo
    echo "$linha" | sudo tee -a /mnt/c/Windows/System32/drivers/etc/hosts > /dev/null
    echo "Linha adicionada ao arquivo."
fi 

echo Update "/etc/hosts" dos nodes

ansible-playbook ./ansible/update-hosts.yaml -i ../01\ -\ preparar-ambiente/inventory/01-inventory.yaml
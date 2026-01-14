#!/bin/bash

set -e

source .env

read -r -p "Do you want to install k3s? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "Installing k3s..."
    ansible-playbook playbooks/install-controller.yaml -i  ./inventory.yaml

    scp sauron@morgul:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    echo "k3s installation completed!"
else
    echo "Skipping k3s installation..."
fi

echo "Configuring Secrets for Flagr..."
cd  ./flagr
./install.sh
cd ..
echo "... Secrets for Flagr configured successfully!"

echo "Configuring local cluster DNS..."
kubectl apply -f ./dns/
echo "... Local cluster DNS configured successfully!"

echo "Configuring Secrets and Realms for Keycloak..."
cd ./keycloak
./install.sh
cd ..
echo "... Secrets and Realms for Keycloak configured successfully!"

echo "Installing ArgoCD..."
cd ./argocd
./install.sh
cd ..
defaultPass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

sleep 10
echo "##########################################"
echo "##  ArgoCD installed successfully!       ##"
echo "##########################################"
echo "##### DEFAULT PASSWORD FOR ADMIN IS $defaultPass #####"
echo
echo
echo
echo "Before continue, you need to:"
echo "  1. Access https://longhorn.home.arpa and configure node disk, adding tags 'ssd' to disk and node"
read -r -p "Press Enter to continue..."
echo "  2. Access https://openbao.home.arpa and unseal the vault"
read -r -p "Press Enter to continue..."
echo "  3. Check keycloak import"
read -r -p "Press Enter to continue..."
echo "  4. Access ArgoCD UI at https://argocd.home.arpa and change admin password"
echo "  5. Check if any application still progressing"
read -r -p "Press Enter to continue..."

echo "Rancher Post installation..."
cd ./rancher
./install.sh
cd ..
echo "Rancher post installation done!"

echo "Import this certificate into your browser to avoid TLS issues:"
kubectl -n cert-manager get secret home-arpa-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > home-arpa-ca.crt
echo "Certificate exported to ./home-arpa-ca.crt"

echo "All done!"

echo "if you need to uninstall everything, run ./uninstall.sh"

#!/bin/bash

set -e

source .env

read -r -p "Do you want prepare the controller server? (y/yes to confirm): " prepare_server
if [[ "$prepare_server" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "Running ansible prepare-server.yamly"
    ansible-playbook playbooks/prepare-server.yaml -i inventory.yaml
    echo "Server preparation is done. You do not need to repeat this again."
fi


read -r -p "Do you want to install k3s? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "Removing databases"
    cd ./databases
    ./configure.sh
    cd ..    
    echo "Installing k3s..."
    ansible-playbook playbooks/install-controller.yaml -i  ./inventory.yaml
    sleep 3
    scp sauron@morgul:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    echo "Test cluster access"
    kubectl get nodes -A
    echo "If fails, try open a new terminal and manually copy the ~/.kube/config file to this machine" 
    read -r -p "Press Enter to continue..."
    echo "k3s installation completed!"
else
    echo "Skipping k3s installation..."
fi
echo "#####################################################################################"
echo

read -r -p "Do you want to configure secrets? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then

    echo "Configuring Secrets for Flagr..."
    cd  ./flagr
    ./install.sh
    cd ..
    echo "... Secrets for Flagr configured successfully!"
    echo

    echo "Configuring local cluster DNS..."
    kubectl apply -f ./dns/
    echo "... Local cluster DNS configured successfully!"
    echo

    echo "Configuring Secrets and Realms for Keycloak..."
    cd ./keycloak
    ./install.sh
    cd ..
    echo "... Secrets and Realms for Keycloak configured successfully!"
    echo

    echo "Configuring forgejo secrets"
    cd ./forgejo
    ./configure.sh
    cd ..
    echo

    echo "Configuring secrets for Open-WebUI"
    cd ./open-webui
    ./install.sh
    cd ..
    echo
else
    echo "Skipping secrets creation"
fi
echo "#####################################################################################"
echo

read -r -p "Do you want to install ArgoCD? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then
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
else
    echo "Skipping ArgoCD instalation"    
fi    
echo "#####################################################################################"
echo
echo
echo "Before continue, you need to:"
echo "  1. Access https://longhorn.home.arpa and configure node disk, adding tags 'ssd' to disk and node"
read -r -p "Press Enter to continue..."


read -r -p "Do you want to auto-unseal openBao? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    cd openbao
    POD_NAME=openbao-0 ./init.sh
    cd ..
    echo "Openbao initialized"
else
    echo "  2. Access https://openbao.home.arpa and unseal the vault"
    read -r -p "Press Enter to continue..."
    echo "Openbao initialized"    
fi
echo "#####################################################################################"
echo

echo "  3. Check keycloak import"
read -r -p "Press Enter to continue..."
echo "#####################################################################################"
echo

echo "  4. Access ArgoCD UI at https://argocd.home.arpa and change admin password"
echo "  5. Check if any application still progressing"
read -r -p "Press Enter to continue..."
echo "#####################################################################################"
echo

read -r -p "Do you want execute Rancher post-installation? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "Rancher Post installation..."
    cd ./rancher
    ./install.sh
    cd ..
    echo "Rancher post installation done!"
else
    echo "Rancher post-installation skipped. You may need to run ./rancher/install.sh"
    echo
fi
echo "#####################################################################################"
echo

echo "Import this certificate into your browser to avoid TLS issues:"
kubectl -n cert-manager get secret home-arpa-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > home-arpa-ca.crt
echo "Certificate exported to ./home-arpa-ca.crt"
echo "#####################################################################################"
echo

read -r -p "Do you want to setup flagr secrets automatically? (y/yes to confirm): " install_k3s
if [[ "$install_k3s" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    echo "Make sure that Keycloak has imported clients and database is on-line"
    echo "(you need to have docker installed)"
    read -r -p "Press Enter to continue..."
    cd ./flagr
    ./postinstall.sh
    cd ..
    echo "Secrets installed successfuly"
fi
echo "#####################################################################################"
echo
defaultPass=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
echo "##### DEFAULT PASSWORD FOR ADMIN at ARGOCD IS $defaultPass #####"
echo "All done!"
echo
echo "if you need to uninstall everything, run ./uninstall.sh"

#!/bin/bash
set -e
source .env

read -r -p "Turn Longhorn ready for deletion? (y/yes to confirm): " prepare_server
if [[ "$prepare_server" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
fi

ansible-playbook playbooks/uninstall-controller.yaml -i  ./inventory.yaml

echo "K3s uninstalled successfully!"

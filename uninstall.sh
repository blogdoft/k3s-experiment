#!/bin/bash
set -e
source .env

kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
ansible-playbook playbooks/uninstall-controller.yaml -i  ./inventory.yaml

echo "K3s uninstalled successfully!"
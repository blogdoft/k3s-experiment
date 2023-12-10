ansible all -b -m copy -a "src=./voltage.sh dest=~/voltage.sh" -i ./inventory/01-inventory.yaml
ansible all -b -m shell -a "bash ~/voltage.sh" -i ./inventory/01-inventory.yaml
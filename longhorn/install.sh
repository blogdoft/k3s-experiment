kubectl apply -f longhorn.yaml
kubectl wait --for=condition=Ready pods --all -n longhorn-system


# Turn longhorn default class (execute at controller)
# sudo cp /var/lib/rancher/k3s/server/manifests/local-storage.yaml /var/lib/rancher/k3s/server/manifests/custom-local-storage.yaml

# sudo sed -i -e "s/storageclass.kubernetes.io\/is-default-class: \"true\"/storageclass.kubernetes.io\/is-default-class: \"false\"/g" /var/lib/rancher/k3s/server/manifests/custom-local-storage.yaml

kubectl apply -f ingress.yaml
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].ip}'=192.168.1.145 ingress/longhorn-system-ingress -n longhorn-system

kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
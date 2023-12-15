#!/bin/bash

export IPADDRESS=127.0.0.1
export HOSTNAME=registry.cube.local
export DOCKER_IMAGETAG=latest
export DOCKER_REPOSITORYNAME=docker-redis-toggler-api
export DOCKER_REGISTRY=$HOSTNAME:5000
export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres-server postgres-container-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
export DATABASE_CONNECTIONSTRING="Server=postgres-server.postgres.svc.local;Port=5432;Database=WebApiDB;User Id=postgres;Password=$POSTGRES_PASSWORD;"
export NAMESPACE="redis-toggler"



dotnet publish -o ./app -c Release
cd eng/docker
docker compose build
cd ../..
rm ./app -rf

docker tag $DOCKER_REPOSITORYNAME:$DOCKER_IMAGETAG $DOCKER_REGISTRY/$DOCKER_REPOSITORYNAME:$DOCKER_IMAGETAG   
docker push $DOCKER_REGISTRY/$DOCKER_REPOSITORYNAME:$DOCKER_IMAGETAG

rm .deploy -rf
mkdir .deploy
cd .deploy
cp ../eng/.k8s/. ./ -rf


for filename in *.yaml; do
    echo "Replacing $filename"
    envsubst < $filename > tmp.yml
    mv tmp.yml $filename
done;

kubectl delete namespace $NAMESPACE
kubectl apply -n $NAMESPACE -f '*.yaml'
kubectl rollout status -n $NAMESPACE -f '*.yaml' --request-timeout 60s
kubectl wait --namespace redis-toggler --for=condition=ready pod --all  
cd ..

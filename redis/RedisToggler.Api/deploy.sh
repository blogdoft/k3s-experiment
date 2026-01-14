#!/bin/bash
set -e

export IPADDRESS=127.0.0.1
export HOSTNAME=registry.home.arpa
export DOCKER_IMAGETAG=latest
export DOCKER_REPOSITORYNAME=docker-redis-toggler-api
export DOCKER_REGISTRY=$HOSTNAME
export POSTGRES_PASSWORD="$1m0n$41m0n"
export DATABASE_CONNECTIONSTRING="Server=192.168.1.212;Port=5432;Database=WebApiDB;User Id=postgres;Password=$POSTGRES_PASSWORD;"
export NAMESPACE="redis-toggler"

dotnet publish -o ./app -c Release

# Register QEMU/binfmt helpers only when a helper container is not already running.
# This avoids re-running the registration if another process already started it.
docker run --rm --privileged tonistiigi/binfmt --install all
docker buildx create --name mybuilder --use

docker buildx build \
  --builder mybuilder \
  --platform linux/arm64 \
  --build-arg PUBLISH_FOLDER=app/ \
  -f ./eng/docker/dockerfile \
  -t $DOCKER_REGISTRY/$DOCKER_REPOSITORYNAME:$DOCKER_IMAGETAG \
  --load \
  .

rm ./app -rf

docker push $DOCKER_REGISTRY/$DOCKER_REPOSITORYNAME:$DOCKER_IMAGETAG 

docker buildx rm mybuilder

docker image rm $DOCKER_REGISTRY/$DOCKER_REPOSITORYNAME:$DOCKER_IMAGETAG 

docker image prune -a -f


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
kubectl rollout status -n $NAMESPACE deployment/redis-toggler-deploy --request-timeout 60s
kubectl wait --namespace $NAMESPACE --for=condition=ready pod --all  
cd ..

sleep 60s

curl "https://redis-toggler.home.arpa/api/WeatherForecast?fromCache=true&api-version=1.0"
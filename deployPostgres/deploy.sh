#!/bin/bash

kubectl apply -f 01-pvc.yaml
kubectl apply -f 04-service.yaml

helm upgrade --install postgres-container bitnami/postgresql --set persistence.existingClaim=postgres-pvc --set volumePermissions.enabled=true --namespace postgres-server


# ** Please be patient while the chart is being deployed **

# PostgreSQL can be accessed via port 5432 on the following DNS names from within your cluster:

#     postgres-container-postgresql.postgres-server.svc.cluster.local - Read/Write connection

# To get the password for "postgres" run:

#     export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres-server postgres-container-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

# To connect to your database run the following command:

#     kubectl run postgres-container-postgresql-client --rm --tty -i --restart='Never' --namespace postgres-server --image docker.io/bitnami/postgresql:16.1.0-debian-11-r15 --env="PGPASSWORD=$POSTGRES_PASSWORD" \
#       --command -- psql --host postgres-container-postgresql -U postgres -d postgres -p 5432

#     > NOTE: If you access the container using bash, make sure that you execute "/opt/bitnami/scripts/postgresql/entrypoint.sh /bin/bash" in order to avoid the error "psql: local user with ID 1001} does not exist"

# To connect to your database from outside the cluster execute the following commands:

#     kubectl port-forward --namespace postgres-server svc/postgres-container-postgresql 5432:5432 &
#     PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432

# WARNING: The configured password will be ignored on new installation in case when previous PostgreSQL release was deleted through the helm command. In that case, old PVC will have an old password, and setting it through helm won't take effect. Deleting persistent volumes (PVs) will solve the issue.
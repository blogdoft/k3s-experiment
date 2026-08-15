#!/bin/bash

CURRENT_DIR=$(pwd)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

cd ${SCRIPT_DIR}

set -e

source ../.env


run_psql() {
  docker run --rm \
    -e PGPASSWORD="${DATABASE_PASSWORD}" \
    "${DATABASE_IMAGE}" \
    psql \
      -h "${DATABASE_HOST}" \
      -p "${DATABASE_PORT}" \
      -U "${DATABASE_USER}" \
      -d "${DATABASE_MAINTENANCE}" \
      -v ON_ERROR_STOP=1 \
      "$@"
}

echo "Verifying database: ${OWUI_DATABASE}"

DB_EXISTS=$(run_psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${OWUI_DATABASE}';")

if [ "${DB_EXISTS}" = "1" ]; then
  echo "Open-WebUI database already exists. Closing connections and removing database: ${OWUI_DATABASE}"

  run_psql -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '${OWUI_DATABASE}'
      AND pid <> pg_backend_pid();
  "

  run_psql -c "DROP DATABASE \"${OWUI_DATABASE}\";"
fi

echo "Verifying user: ${OWUI_USER}"

ROLE_EXISTS=$(run_psql -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${OWUI_USER}';")

if [ "${ROLE_EXISTS}" = "1" ]; then
  echo "User already exists: ${OWUI_USER}"
  echo "Update user password: ${OWUI_USER}"

  run_psql -c "ALTER ROLE \"${OWUI_USER}\" WITH LOGIN PASSWORD '${OWUI_DBPASS}';"
else
  echo "Create user: ${OWUI_USER}"

  run_psql -c "CREATE ROLE \"${OWUI_USER}\" WITH LOGIN PASSWORD '${OWUI_DBPASS}';"
fi

echo "Create database: ${OWUI_DATABASE}"

run_psql -c "
  CREATE DATABASE \"${OWUI_DATABASE}\"
  WITH
    OWNER \"${OWUI_USER}\"
    TEMPLATE template0
    ENCODING 'UTF8'
    LC_COLLATE 'en_US.UTF-8'
    LC_CTYPE 'en_US.UTF-8';
"
run_psql -c "GRANT ALL PRIVILEGES ON DATABASE \"${OWUI_DATABASE}\" TO ${OWUI_USER}";

echo "Open-WebUI database created."
echo
echo "Processing Secrets"
TEMP_FILE=secrets_temp.yaml
SOURCE_FILE=secrets.yaml
envsubst < "$SOURCE_FILE" > "$TEMP_FILE"
echo "Creating secrets"
kubectl create namespace open-webui \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f $TEMP_FILE -n open-webui
rm $TEMP_FILE

cd $CURRENT_DIR
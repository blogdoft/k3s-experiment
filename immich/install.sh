#!/bin/bash

CURRENT_DIR=$(pwd)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

cd ${SCRIPT_DIR}

set -e

source ../.env

run_psql() {
  local database="$1"
  shift
  docker run --rm \
    -e PGPASSWORD="${DATABASE_PASSWORD}" \
    "${DATABASE_IMAGE}" \
    psql \
      -h "${DATABASE_HOST}" \
      -p "${DATABASE_PORT}" \
      -U "${DATABASE_USER}" \
      -d "${database}" \
      -v ON_ERROR_STOP=1 \
      "$@"
}

echo "Checking VectorChord on ${DATABASE_HOST}"
VCHORD_AVAILABLE=$(run_psql "${DATABASE_MAINTENANCE}" -tAc "SELECT 1 FROM pg_available_extensions WHERE name = 'vchord';")
if [ "${VCHORD_AVAILABLE}" != "1" ]; then
  echo "ERROR: the vchord extension is not available on the Postgres server (Immich v3 requires it)."
  exit 1
fi

echo "Verifying user: ${IMMICH_DB_USER}"
ROLE_EXISTS=$(run_psql "${DATABASE_MAINTENANCE}" -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${IMMICH_DB_USER}';")

if [ "${ROLE_EXISTS}" = "1" ]; then
  echo "User already exists, updating password: ${IMMICH_DB_USER}"
  run_psql "${DATABASE_MAINTENANCE}" -c "ALTER ROLE \"${IMMICH_DB_USER}\" WITH LOGIN PASSWORD '${IMMICH_DB_PASSWORD}';"
else
  echo "Create user: ${IMMICH_DB_USER}"
  run_psql "${DATABASE_MAINTENANCE}" -c "CREATE ROLE \"${IMMICH_DB_USER}\" WITH LOGIN PASSWORD '${IMMICH_DB_PASSWORD}';"
fi

echo "Verifying database: ${IMMICH_DB_NAME}"
DB_EXISTS=$(run_psql "${DATABASE_MAINTENANCE}" -tAc "SELECT 1 FROM pg_database WHERE datname = '${IMMICH_DB_NAME}';")

# Unlike the other components, the database is never dropped: it holds the library metadata.
if [ "${DB_EXISTS}" = "1" ]; then
  echo "Database already exists, keeping it: ${IMMICH_DB_NAME}"
else
  echo "Create database: ${IMMICH_DB_NAME}"
  run_psql "${DATABASE_MAINTENANCE}" -c "
    CREATE DATABASE \"${IMMICH_DB_NAME}\"
    WITH
      OWNER \"${IMMICH_DB_USER}\"
      TEMPLATE template0
      ENCODING 'UTF8'
      LC_COLLATE 'en_US.UTF-8'
      LC_CTYPE 'en_US.UTF-8';
  "
fi

# Immich creates these on startup, but its role is not a superuser and some are not trusted extensions.
echo "Enabling extensions"
run_psql "${IMMICH_DB_NAME}" -c "
  CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
  CREATE EXTENSION IF NOT EXISTS cube;
  CREATE EXTENSION IF NOT EXISTS earthdistance;
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
  CREATE EXTENSION IF NOT EXISTS unaccent;
  CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";
"

echo "Immich database ready."
echo
echo "Processing Secrets"
TEMP_FILE=secrets_temp.yaml
SOURCE_FILE=secrets.yaml
envsubst < "$SOURCE_FILE" > "$TEMP_FILE"
echo "Creating secrets"
kubectl create namespace immich \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f $TEMP_FILE -n immich
rm $TEMP_FILE

cd $CURRENT_DIR

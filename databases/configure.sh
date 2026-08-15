#!/usr/bin/env sh

set -e

PG_IMAGE="postgres:14-alpine"

PG_HOST="${DATABASE_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${K3S_DB_USER:-postgres}"
PG_PASSWORD="${DATABASE_PASSWORD:-postgres}"
PG_MAINTENANCE_DB="${PG_MAINTENANCE_DB:-postgres}"

DATABASES="flagr k3s kc-cluster"

run_psql() {
  docker run --rm \
    -e PGPASSWORD="${PG_PASSWORD}" \
    "${PG_IMAGE}" \
    psql \
      -h "${PG_HOST}" \
      -p "${PG_PORT}" \
      -U "${PG_USER}" \
      -d "${PG_MAINTENANCE_DB}" \
      -v ON_ERROR_STOP=1 \
      "$@"
}

for DB_NAME in ${DATABASES}; do
  echo "Verificando database: ${DB_NAME}"

  DB_EXISTS=$(run_psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}';")

  if [ "${DB_EXISTS}" = "1" ]; then
    echo "Database existe. Encerrando conexões e removendo: ${DB_NAME}"

    run_psql -c "
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '${DB_NAME}'
        AND pid <> pg_backend_pid();
    "

    run_psql -c "DROP DATABASE \"${DB_NAME}\";"
  else
    echo "Database não existe, nada para remover: ${DB_NAME}"
  fi

  echo "Criando database: ${DB_NAME}"
  run_psql -c "CREATE DATABASE \"${DB_NAME}\";"
done

echo "Databases recriados com sucesso."
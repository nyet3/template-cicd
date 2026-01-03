#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER keycloak WITH PASSWORD 'keycloakpass';
    ALTER ROLE keycloak WITH CREATEDB CREATEROLE INHERIT LOGIN;
    CREATE DATABASE keycloak OWNER keycloak;
EOSQL

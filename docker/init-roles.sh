#!/bin/bash
# Runs once, on first database init, as supabase_admin.
#
# The supabase/postgres image ships the extensions and supabase_admin, but NOT
# the service roles GoTrue / PostgREST / storage-api connect as. On Supabase
# Cloud those are created by platform tooling; self-hosted, we create them here.
# Without this, auth and rest crash-loop on SASL auth failures.
set -e

psql -v ON_ERROR_STOP=1 --username supabase_admin --dbname postgres <<-EOSQL
    -- PostgREST request roles. anon is the unauthenticated role; the JWT's
    -- "role" claim switches to authenticated or service_role.
    DO \$\$ BEGIN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;

    DO \$\$ BEGIN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;

    -- BYPASSRLS: service_role is the admin path used by server actions.
    DO \$\$ BEGIN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;

    -- The role PostgREST logs in as; it assumes one of the three above per request.
    DO \$\$ BEGIN
        CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD '${POSTGRES_PASSWORD}';
    EXCEPTION WHEN duplicate_object THEN
        ALTER ROLE authenticator WITH PASSWORD '${POSTGRES_PASSWORD}';
    END \$\$;

    GRANT anon, authenticated, service_role TO authenticator;

    -- GoTrue owns the auth schema.
    DO \$\$ BEGIN
        CREATE ROLE supabase_auth_admin LOGIN NOINHERIT CREATEROLE PASSWORD '${POSTGRES_PASSWORD}';
    EXCEPTION WHEN duplicate_object THEN
        ALTER ROLE supabase_auth_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
    END \$\$;
    CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
    GRANT CREATE ON DATABASE postgres TO supabase_auth_admin;
    ALTER ROLE supabase_auth_admin SET search_path = 'auth';

    -- storage-api owns the storage schema.
    DO \$\$ BEGIN
        CREATE ROLE supabase_storage_admin LOGIN NOINHERIT CREATEROLE PASSWORD '${POSTGRES_PASSWORD}';
    EXCEPTION WHEN duplicate_object THEN
        ALTER ROLE supabase_storage_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
    END \$\$;
    CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
    GRANT CREATE ON DATABASE postgres TO supabase_storage_admin;
    ALTER ROLE supabase_storage_admin SET search_path = 'storage';

    -- Supabase Cloud exposes a "postgres" superuser; mirror it so DATABASE_URL
    -- and the migration runner behave the same here as against a cloud project.
    DO \$\$ BEGIN
        CREATE ROLE postgres LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD '${POSTGRES_PASSWORD}';
    EXCEPTION WHEN duplicate_object THEN
        ALTER ROLE postgres WITH PASSWORD '${POSTGRES_PASSWORD}';
    END \$\$;

    -- Baseline grants so RLS policies are what actually restrict access,
    -- rather than missing schema privileges.
    GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;

    -- storage-api and GoTrue work like PostgREST: they connect as a fixed
    -- login role and SET ROLE per request from the JWT. That requires
    -- MEMBERSHIP of the request roles. Missing this on supabase_storage_admin
    -- made every upload fail RLS, including service-key writes.
    -- Placed last: the roles above must exist first.
    GRANT anon, authenticated, service_role TO supabase_storage_admin;
    GRANT anon, authenticated, service_role TO supabase_auth_admin;
EOSQL

echo "[init-roles] service roles created and passwords aligned"

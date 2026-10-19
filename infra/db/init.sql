-- Inicializacion de base de datos para el piloto HashiCorp Vault + PostgreSQL
-- Se ejecuta automaticamente en el contenedor vm-db (172.28.0.20) sobre la BBDD pilotdb

-- 1. Tabla de auditoria de conexiones y rotacion de credenciales
CREATE TABLE IF NOT EXISTS public.connection_audit_log (
    id BIGSERIAL PRIMARY KEY,
    credential_mode VARCHAR(16) NOT NULL, -- 'DYNAMIC' | 'STATIC'
    db_username VARCHAR(128) NOT NULL,
    backend_pid INTEGER NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Rol base de permisos para la aplicacion (tanto usuarios dinamicos como estaticos)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'pilot_app_group') THEN
        CREATE ROLE pilot_app_group NOLOGIN;
    END IF;
END
$$;

GRANT CONNECT ON DATABASE pilotdb TO pilot_app_group;
GRANT USAGE ON SCHEMA public TO pilot_app_group;
GRANT SELECT, INSERT ON public.connection_audit_log TO pilot_app_group;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pilot_app_group;

-- 3. Superusuario de administracion para que HashiCorp Vault gestione usuarios dinamicos y rote claves
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'vault_admin') THEN
        CREATE ROLE vault_admin WITH LOGIN SUPERUSER CREATEROLE PASSWORD 'vault_admin_pwd';
    END IF;
END
$$;

-- 4. Usuario fijo para el rol estatico de Vault (postgres-static-role)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_static_user') THEN
        CREATE ROLE app_static_user WITH LOGIN PASSWORD 'initial_static_pwd' IN ROLE pilot_app_group;
    END IF;
END
$$;

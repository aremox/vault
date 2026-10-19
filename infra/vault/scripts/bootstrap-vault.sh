#!/bin/sh
set -e

export VAULT_ADDR="http://127.0.0.1:8200"
BOOTSTRAP_DIR="/vault/bootstrap"
mkdir -p "$BOOTSTRAP_DIR" /vault/file
rm -f "$BOOTSTRAP_DIR/ready"

echo "[vm-vault] Arrancando HashiCorp Vault Server (file storage)..."
vault server -config=/vault/config/config.hcl &
VAULT_PID=$!

# Esperar a que el listener HTTP de Vault responda
echo "[vm-vault] Esperando listener HTTP en $VAULT_ADDR..."
until wget -qO- "$VAULT_ADDR/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" >/dev/null 2>&1; do
  sleep 1
done

# 1. Inicializar Vault si no esta inicializado
INIT_STATUS=$(vault status -format=json 2>/dev/null | sed -n 's/.*"initialized":[[:space:]]*\(true\|false\).*/\1/p')
if [ "$INIT_STATUS" != "true" ]; then
  echo "[vm-vault] Inicializando Vault Operator (1 share, 1 threshold)..."
  INIT_JSON=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
  echo "$INIT_JSON" > "$BOOTSTRAP_DIR/init.json"
  UNSEAL_KEY=$(echo "$INIT_JSON" | sed -n '/"unseal_keys_b64":/,/]/p' | grep -v "unseal_keys_b64" | grep -v "]" | tr -d ' ",\r\n')
  ROOT_TOKEN=$(echo "$INIT_JSON" | sed -n 's/.*"root_token":[[:space:]]*"\([^"]*\)".*/\1/p')
  printf "%s" "$UNSEAL_KEY" > "$BOOTSTRAP_DIR/unseal.key"
  printf "%s" "$ROOT_TOKEN" > "$BOOTSTRAP_DIR/root.token"
  chmod 0644 "$BOOTSTRAP_DIR/root.token" "$BOOTSTRAP_DIR/unseal.key"
fi

# 2. Desellar Vault si esta sellado
SEALED_STATUS=$(vault status -format=json 2>/dev/null | sed -n 's/.*"sealed":[[:space:]]*\(true\|false\).*/\1/p')
if [ "$SEALED_STATUS" = "true" ]; then
  echo "[vm-vault] Desellando Vault Server..."
  UNSEAL_KEY=$(cat "$BOOTSTRAP_DIR/unseal.key")
  vault operator unseal "$UNSEAL_KEY" >/dev/null
fi

export VAULT_TOKEN=$(cat "$BOOTSTRAP_DIR/root.token")
echo "[vm-vault] Vault inicializado y desellado (Sealed: false)."

# 3. Esperar a que PostgreSQL (vm-db 172.29.0.20:5432) acepte conexiones TCP
echo "[vm-vault] Esperando disponibilidad de vm-db (172.29.0.20:5432)..."
until nc -z 172.29.0.20 5432 >/dev/null 2>&1; do
  sleep 1
done

# 4. Habilitar y configurar motor de secretos de Base de Datos
if ! vault secrets list | grep -q "^database/"; then
  echo "[vm-vault] Habilitando motor database/..."
  vault secrets enable database
fi

echo "[vm-vault] Configurando conexion PostgreSQL (postgres-pilot)..."
vault write database/config/postgres-pilot \
  plugin_name=postgresql-database-plugin \
  allowed_roles="postgres-dynamic-role,postgres-static-role" \
  connection_url="postgresql://{{username}}:{{password}}@172.29.0.20:5432/pilotdb?sslmode=disable" \
  username="vault_admin" \
  password="vault_admin_pwd"

echo "[vm-vault] Configurando rol dinamico postgres-dynamic-role (TTL=60s, max_ttl=120s)..."
vault write database/roles/postgres-dynamic-role \
  db_name=postgres-pilot \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE pilot_app_group;" \
  revocation_statements="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}'; DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="60s" \
  max_ttl="120s"

echo "[vm-vault] Configurando rol estatico postgres-static-role (rotation_period=60s)..."
vault write database/static-roles/postgres-static-role \
  db_name=postgres-pilot \
  username="app_static_user" \
  rotation_statements="ALTER USER \"{{name}}\" WITH PASSWORD '{{password}}';" \
  rotation_period="60s"

# 5. Cargar politica y habilitar AppRole
echo "[vm-vault] Cargando politica app-db-policy y configurando AppRole spring-app-role..."
vault policy write app-db-policy /vault/policies/app-db-policy.hcl

if ! vault auth list | grep -q "^approle/"; then
  vault auth enable approle
fi

vault write auth/approle/role/spring-app-role \
  token_policies="app-db-policy" \
  token_ttl="10m" \
  token_max_ttl="30m" \
  secret_id_ttl="10m" \
  secret_id_num_uses=0

touch "$BOOTSTRAP_DIR/ready"
echo "[vm-vault] Aprovisionamiento de Vault completado con exito."

wait $VAULT_PID

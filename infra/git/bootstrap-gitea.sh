#!/bin/bash
set -e

GITEA_WORK_DIR="/data/gitea"
GITEA_CUSTOM="/data/gitea"
APP_INI="/data/gitea/conf/app.ini"
READY_FILE="/run/gitea/ready"
GITEA_ADMIN_USER="pilot-admin"
GITEA_ADMIN_PASS="gitea_secret_password_2026"
GITEA_ADMIN_EMAIL="pilot-admin@vault-pilot.local"
REPO_NAME="pilot-config"

rm -f "$READY_FILE"
mkdir -p /data/gitea/conf /data/gitea/data /data/gitea/log /data/git /run/gitea

if [ ! -f "$APP_INI" ]; then
  cat > "$APP_INI" <<EOF
APP_NAME = Vault Pilot Git Server (Gitea)
RUN_USER = gitea
RUN_MODE = prod
WORK_PATH = /data/gitea

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/data/gitea.db

[repository]
ROOT = /data/git/repositories
DEFAULT_BRANCH = main

[server]
DOMAIN = 172.29.0.50
HTTP_PORT = 3000
ROOT_URL = http://localhost:13000/
DISABLE_SSH = true
OFFLINE_MODE = true

[security]
INSTALL_LOCK = true
SECRET_KEY = VaultPilotGiteaSecretKey2026Lab

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false

[log]
MODE = console
LEVEL = Warn
EOF
fi

chown -R gitea /data /run/gitea

echo "[vm-git] Iniciando servidor Gitea en 0.0.0.0:3000..."
su-exec gitea gitea web --config "$APP_INI" --custom-path "$GITEA_CUSTOM" --work-path "$GITEA_WORK_DIR" &
GITEA_PID=$!

echo "[vm-git] Esperando a que la API HTTP de Gitea responda en http://127.0.0.1:3000/api/v1/version..."
until curl -sf http://127.0.0.1:3000/api/v1/version >/dev/null 2>&1; do
  sleep 1
done

echo "[vm-git] Asegurando usuario administrador $GITEA_ADMIN_USER..."
if ! su-exec gitea gitea admin user list --config "$APP_INI" --custom-path "$GITEA_CUSTOM" --work-path "$GITEA_WORK_DIR" | awk '{print $2}' | grep -qx "$GITEA_ADMIN_USER"; then
  su-exec gitea gitea admin user create \
    --config "$APP_INI" \
    --custom-path "$GITEA_CUSTOM" \
    --work-path "$GITEA_WORK_DIR" \
    --username "$GITEA_ADMIN_USER" \
    --password "$GITEA_ADMIN_PASS" \
    --email "$GITEA_ADMIN_EMAIL" \
    --admin \
    --must-change-password=false
else
  su-exec gitea gitea admin user change-password \
    --config "$APP_INI" \
    --custom-path "$GITEA_CUSTOM" \
    --work-path "$GITEA_WORK_DIR" \
    --username "$GITEA_ADMIN_USER" \
    --password "$GITEA_ADMIN_PASS" \
    --must-change-password=false || true
fi

REPO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" "http://127.0.0.1:3000/api/v1/repos/${GITEA_ADMIN_USER}/${REPO_NAME}")
if [ "$REPO_STATUS" != "200" ]; then
  echo "[vm-git] Creando repositorio ${GITEA_ADMIN_USER}/${REPO_NAME}..."
  curl -sf -X POST "http://127.0.0.1:3000/api/v1/user/repos" \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${REPO_NAME}\",
      \"description\": \"Repositorio centralizado de configuracion para Spring Cloud Config Server\",
      \"private\": false,
      \"auto_init\": false,
      \"default_branch\": \"main\"
    }" >/dev/null
fi

FILE_BODY=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" "http://127.0.0.1:3000/api/v1/repos/${GITEA_ADMIN_USER}/${REPO_NAME}/contents/vault-rotation-pilot.yml" || true)
if ! echo "$FILE_BODY" | grep -q '"name":"vault-rotation-pilot.yml"'; then
  echo "[vm-git] Creando commit inicial de vault-rotation-pilot.yml..."
  INITIAL_YAML=$(cat <<'YAML'
pilot:
  config:
    environment: "production-lab"
    banner: "Configuracion centralizada desde Gitea + Spring Cloud Config"
    custom-tag: "git-v1"
    refresh-counter: 1
YAML
)
  INITIAL_B64=$(printf "%s\n" "$INITIAL_YAML" | base64 | tr -d '\r\n')
  curl -sf -X POST "http://127.0.0.1:3000/api/v1/repos/${GITEA_ADMIN_USER}/${REPO_NAME}/contents/vault-rotation-pilot.yml" \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{
      \"content\": \"${INITIAL_B64}\",
      \"message\": \"feat(config): initial Spring Cloud Config properties for vault-rotation-pilot\",
      \"branch\": \"main\"
    }" >/dev/null
fi

touch "$READY_FILE"
echo "[vm-git] Servidor Gitea listo en http://172.29.0.50:3000 (Host http://localhost:13000) con repo ${GITEA_ADMIN_USER}/${REPO_NAME}."

wait $GITEA_PID

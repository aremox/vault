#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

BASE_URL="http://localhost:18080"

echo "=================================================================="
echo " VERIFICACION DE CONSOLA WEB ANIMADA Y SPRING CLOUD CONFIG"
echo " Endpoint base: $BASE_URL"
echo "=================================================================="

# 1. Esperar a que el servidor web Spring Boot en vm-app responda HTTP 200
echo ""
echo "[1/6] Esperando disponibilidad de $BASE_URL/ ..."
READY="false"
for i in $(seq 1 40); do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    READY="true"
    break
  fi
  sleep 2
done

if [ "$READY" != "true" ]; then
  echo "ERROR: $BASE_URL/ no respondio HTTP 200"
  docker logs --tail 30 vm-app
  exit 1
fi

HTML_BODY=$(curl -fsS "$BASE_URL/")
for required_id in "arch-svg" "node-git" "node-config-server" "card-spring-config" "btn-refresh-config"; do
  if ! echo "$HTML_BODY" | grep -q "$required_id"; then
    echo "ERROR: El HTML servido no contiene el elemento esperado ($required_id)."
    exit 1
  fi
done
echo "  [OK] GET / responde HTTP 200 y contiene los 6 nodos SVG (#node-git, #node-config-server) y la tarjeta Spring Cloud Config"

# 2. Verificar recursos estaticos CSS y JS
echo ""
echo "[2/6] Verificando carga de /styles.css y /app.js..."
curl -fsS "$BASE_URL/styles.css" >/dev/null
curl -fsS "$BASE_URL/app.js" >/dev/null
echo "  [OK] /styles.css (200) y /app.js (200) servidos correctamente"

# 3. Verificar GET /api/pilot/state con las 6 VMs y bloque springCloudConfig
echo ""
echo "[3/6] Verificando estado en tiempo real en GET /api/pilot/state..."
STATE_JSON=$(curl -fsS "$BASE_URL/api/pilot/state" | tr -d '\r')
for expected_key in '"subnet":"172.29.0.0/24"' '"172.29.0.10"' '"172.29.0.20"' '"172.29.0.30"' '"172.29.0.40"' '"172.29.0.50"' '"172.29.0.60"' '"springCloudConfig"' '"dynamic"' '"static"' '"activeSessions"' '"recentAudits"'; do
  if ! echo "$STATE_JSON" | grep -q "$expected_key"; then
    echo "ERROR: No se encontro $expected_key en /api/pilot/state"
    echo "$STATE_JSON"
    exit 1
  fi
done

INIT_DYN_USER=$(echo "$STATE_JSON" | docker exec -i vm-app jq -r '.credentials.dynamic.username' | tr -d '\r\n')
INIT_STAT_HASH=$(echo "$STATE_JSON" | docker exec -i vm-app jq -r '.credentials.static.passwordHash' | tr -d '\r\n')
INIT_STAT_PID=$(echo "$STATE_JSON" | docker exec -i vm-app jq -r '.credentials.static.currentBackendPid' | tr -d '\r\n')
INIT_CFG_TAG=$(echo "$STATE_JSON" | docker exec -i vm-app jq -r '.springCloudConfig.customTag' | tr -d '\r\n')
INIT_CFG_SIG=$(echo "$STATE_JSON" | docker exec -i vm-app jq -r '.springCloudConfig.vaultKvSignature' | tr -d '\r\n')

echo "  [OK] Estado inicial -> Dynamic: $INIT_DYN_USER | Static Hash: $INIT_STAT_HASH | Config Tag: $INIT_CFG_TAG | Vault KV: $INIT_CFG_SIG"

# 4. Probar POST /api/pilot/rotate/static
echo ""
echo "[4/6] Probando rotacion manual estatica (POST /api/pilot/rotate/static)..."
ROT_STAT_JSON=$(curl -fsS -X POST "$BASE_URL/api/pilot/rotate/static" | tr -d '\r')
ROT_STAT_OK=$(echo "$ROT_STAT_JSON" | docker exec -i vm-app jq -r '.rotated' | tr -d '\r\n')
NEW_STAT_HASH=$(echo "$ROT_STAT_JSON" | docker exec -i vm-app jq -r '.credential.passwordHash' | tr -d '\r\n')
NEW_STAT_PID=$(echo "$ROT_STAT_JSON" | docker exec -i vm-app jq -r '.credential.currentBackendPid' | tr -d '\r\n')

if [ "$ROT_STAT_OK" != "true" ] || [ "$NEW_STAT_HASH" = "$INIT_STAT_HASH" ]; then
  echo "ERROR: POST /api/pilot/rotate/static no roto la clave estatica: $ROT_STAT_JSON"
  exit 1
fi
echo "  [OK] Rotacion estatica via API Web -> Hash: $INIT_STAT_HASH -> $NEW_STAT_HASH | PID: $INIT_STAT_PID -> $NEW_STAT_PID"

# 5. Probar POST /api/pilot/rotate/dynamic
echo ""
echo "[5/6] Probando rotacion manual dinamica (POST /api/pilot/rotate/dynamic)..."
ROT_DYN_JSON=$(curl -fsS -X POST "$BASE_URL/api/pilot/rotate/dynamic" | tr -d '\r')
ROT_DYN_OK=$(echo "$ROT_DYN_JSON" | docker exec -i vm-app jq -r '.rotated' | tr -d '\r\n')
NEW_DYN_USER=$(echo "$ROT_DYN_JSON" | docker exec -i vm-app jq -r '.credential.username' | tr -d '\r\n')
NEW_DYN_PID=$(echo "$ROT_DYN_JSON" | docker exec -i vm-app jq -r '.credential.currentBackendPid' | tr -d '\r\n')

if [ "$ROT_DYN_OK" != "true" ] || [ "$NEW_DYN_USER" = "$INIT_DYN_USER" ]; then
  echo "ERROR: POST /api/pilot/rotate/dynamic no genero nuevo usuario efimero: $ROT_DYN_JSON"
  exit 1
fi
echo "  [OK] Rotacion dinamica via API Web -> Usuario: $INIT_DYN_USER -> $NEW_DYN_USER (PID $NEW_DYN_PID)"

# 6. Probar POST /api/pilot/config/refresh (Commit en Gitea + Rotacion KV en Vault + @RefreshScope)
echo ""
echo "[6/6] Probando Commit en Gitea + Refresh Spring Cloud (@RefreshScope) via POST /api/pilot/config/refresh..."
CFG_REFRESH_JSON=$(curl -fsS -X POST "$BASE_URL/api/pilot/config/refresh" | tr -d '\r')
CFG_REFRESH_OK=$(echo "$CFG_REFRESH_JSON" | docker exec -i vm-app jq -r '.refreshed' | tr -d '\r\n')
NEW_CFG_TAG=$(echo "$CFG_REFRESH_JSON" | docker exec -i vm-app jq -r '.springCloudConfig.customTag' | tr -d '\r\n')
NEW_CFG_SIG=$(echo "$CFG_REFRESH_JSON" | docker exec -i vm-app jq -r '.springCloudConfig.vaultKvSignature' | tr -d '\r\n')
NEW_CFG_SHA=$(echo "$CFG_REFRESH_JSON" | docker exec -i vm-app jq -r '.springCloudConfig.lastCommitSha' | tr -d '\r\n')

if [ "$CFG_REFRESH_OK" != "true" ] || [ "$NEW_CFG_TAG" = "$INIT_CFG_TAG" ] || [ "$NEW_CFG_SIG" = "$INIT_CFG_SIG" ]; then
  echo "ERROR: POST /api/pilot/config/refresh no actualizo Gitea/Vault KV ni refresco @RefreshScope: $CFG_REFRESH_JSON"
  exit 1
fi
echo "  [OK] Spring Cloud Config Hot-Reload -> Commit Gitea: $NEW_CFG_SHA | Tag: $INIT_CFG_TAG -> $NEW_CFG_TAG | Vault KV: $INIT_CFG_SIG -> $NEW_CFG_SIG"

echo ""
echo "=================================================================="
echo " RESULTADO: CONSOLA WEB Y ENDPOINTS VERIFICADOS CON EXITO (EXIT 0)"
echo " URL Consola Animada: http://localhost:18080"
echo " URL Servidor Git Gitea: http://localhost:13000"
echo " URL Spring Cloud Config: http://localhost:18888/vault-rotation-pilot/default"
echo "=================================================================="
exit 0

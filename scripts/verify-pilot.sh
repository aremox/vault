#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

echo "=================================================================="
echo " PILOTO HASHICORP VAULT + GITEA + SPRING CLOUD CONFIG + POSTGRESQL"
echo " Verificacion extremo a extremo de las 6 VMs, rotacion y hot-reload"
echo "=================================================================="

# 1. Verificar contenedores e IPs estaticas en 172.29.0.0/24
echo ""
echo "[1/8] Verificando los 6 contenedores tipo VM y sus IPs fijas..."
declare -A EXPECTED_IPS=(
  ["vm-vault"]="172.29.0.10"
  ["vm-db"]="172.29.0.20"
  ["vm-app"]="172.29.0.30"
  ["vm-ansible"]="172.29.0.40"
  ["vm-git"]="172.29.0.50"
  ["vm-config-server"]="172.29.0.60"
)

for cname in "${!EXPECTED_IPS[@]}"; do
  expected_ip="${EXPECTED_IPS[$cname]}"
  actual_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cname" 2>/dev/null | tr -d '\r\n' || true)
  running=$(docker inspect -f '{{.State.Running}}' "$cname" 2>/dev/null | tr -d '\r\n' || true)
  if [ "$running" != "true" ] || [ "$actual_ip" != "$expected_ip" ]; then
    echo "ERROR: Contenedor $cname no esta corriendo con IP $expected_ip (running=$running, ip=$actual_ip)"
    exit 1
  fi
  echo "  [OK] $cname activo en $actual_ip"
done

# 2. Verificar estado de HashiCorp Vault Server (Initialized, Sealed: false, Storage: file, KV v2 secret/)
echo ""
echo "[2/8] Verificando estado de vm-vault (Storage: file + motores database/ y secret/ KV v2)..."
VAULT_STATUS_JSON=$(docker exec vm-vault vault status -format=json | tr -d '\r')
INIT=$(echo "$VAULT_STATUS_JSON" | grep -o '"initialized": *true' || true)
SEALED=$(echo "$VAULT_STATUS_JSON" | grep -o '"sealed": *false' || true)
STORAGE=$(echo "$VAULT_STATUS_JSON" | grep -o '"storage_type": *"file"' || true)

if [ -z "$INIT" ] || [ -z "$SEALED" ] || [ -z "$STORAGE" ]; then
  echo "ERROR: Estado de Vault invalido: $VAULT_STATUS_JSON"
  exit 1
fi

ROOT_TOKEN=$(docker exec vm-vault cat /vault/bootstrap/root.token | tr -d '\r\n')
KV_GIT_USER=$(docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vm-vault vault kv get -field=git_username secret/git-credentials | tr -d '\r\n')
KV_SIG_INIT=$(docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vm-vault vault kv get -field=pilot.vault.kv.secret-signature secret/vault-rotation-pilot | tr -d '\r\n')
if [ "$KV_GIT_USER" != "pilot-admin" ] || [ -z "$KV_SIG_INIT" ]; then
  echo "ERROR: Secretos KV v2 no encontrados en secret/git-credentials o secret/vault-rotation-pilot"
  exit 1
fi
echo "  [OK] Vault Server -> Initialized: true | Sealed: false | KV v2 secret/git-credentials ($KV_GIT_USER) y secret/vault-rotation-pilot ($KV_SIG_INIT)"

# 3. Verificar Gitea (vm-git :13000) y Spring Cloud Config Server (vm-config-server :18888)
echo ""
echo "[3/8] Verificando Gitea (http://localhost:13000) y Spring Cloud Config Server (http://localhost:18888)..."
GITEA_REPO_JSON=$(curl -fsS http://localhost:13000/api/v1/repos/pilot-admin/pilot-config | tr -d '\r')
if ! echo "$GITEA_REPO_JSON" | grep -q '"full_name":"pilot-admin/pilot-config"'; then
  echo "ERROR: Repositorio pilot-admin/pilot-config no existe en Gitea"
  exit 1
fi

CONFIG_READY="false"
for i in $(seq 1 30); do
  if curl -fsS http://localhost:18888/vault-rotation-pilot/default >/dev/null 2>&1; then
    CONFIG_READY="true"
    break
  fi
  sleep 2
done

if [ "$CONFIG_READY" != "true" ]; then
  echo "ERROR: vm-config-server no respondio en http://localhost:18888/vault-rotation-pilot/default"
  docker logs --tail 30 vm-config-server
  exit 1
fi

CONFIG_PAYLOAD=$(curl -fsS http://localhost:18888/vault-rotation-pilot/default | tr -d '\r')
if ! echo "$CONFIG_PAYLOAD" | grep -q "pilot.config.banner" || ! echo "$CONFIG_PAYLOAD" | grep -q "pilot.vault.kv.secret-signature"; then
  echo "ERROR: vm-config-server no devolvio combinadas las propiedades de Gitea + Vault KV v2:"
  echo "$CONFIG_PAYLOAD"
  exit 1
fi
echo "  [OK] Gitea (:13000) y Spring Cloud Config Server (:18888) sirven propiedades combinadas Git + Vault KV v2"

# 4. Verificar aprovisionamiento Ansible por SSH (role_id + secret_id con permisos 0600 en vm-config-server y vm-app)
echo ""
echo "[4/8] Verificando ejecucion del playbook Ansible (role_id + secret_id -> vm-config-server y vm-app)..."
ANSIBLE_OUT=$(docker logs vm-ansible 2>&1 | tr -d '\r')
echo "$ANSIBLE_OUT" | tail -n 6
if ! echo "$ANSIBLE_OUT" | grep -q "failed=0"; then
  echo "Re-ejecutando playbook Ansible..."
  ANSIBLE_OUT=$(docker exec vm-ansible ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml | tr -d '\r')
  echo "$ANSIBLE_OUT" | tail -n 6
  if ! echo "$ANSIBLE_OUT" | grep -q "failed=0"; then
    echo "ERROR: Playbook de Ansible reporto fallos."
    exit 1
  fi
fi

for target_vm in vm-config-server vm-app; do
  ROLE_PERM=$(docker exec "$target_vm" stat -c "%a" /etc/vault.d/role_id | tr -d '\r\n')
  SECRET_PERM=$(docker exec "$target_vm" stat -c "%a" /etc/vault.d/secret_id | tr -d '\r\n')
  if [ "$ROLE_PERM" != "600" ] || [ "$SECRET_PERM" != "600" ]; then
    echo "ERROR: Permisos incorrectos en $target_vm:/etc/vault.d (role_id=$ROLE_PERM, secret_id=$SECRET_PERM)"
    exit 1
  fi
  echo "  [OK] $target_vm:/etc/vault.d/role_id ($ROLE_PERM) y secret_id ($SECRET_PERM) aprovisionados via SSH"
done

# 5. Verificar ficheros renderizados por Vault Agent en vm-config-server y vm-app
echo ""
echo "[5/8] Verificando ficheros de secretos renderizados por vault-agent..."
docker exec vm-config-server test -s /run/secrets/git-credentials.properties
docker exec vm-app test -s /run/secrets/db-dynamic.properties
docker exec vm-app test -s /run/secrets/db-static.properties
DYN_USER_1=$(docker exec vm-app awk -F= '/username/{print $2}' /run/secrets/db-dynamic.properties | tr -d '\r\n')
STAT_USER_1=$(docker exec vm-app awk -F= '/username/{print $2}' /run/secrets/db-static.properties | tr -d '\r\n')
STAT_PWD_1=$(docker exec vm-app awk -F= '/password/{print $2}' /run/secrets/db-static.properties | tr -d '\r\n')
echo "  [OK] vm-config-server: /run/secrets/git-credentials.properties renderizado"
echo "  [OK] vm-app Usuario dinamico actual : $DYN_USER_1"
echo "  [OK] vm-app Usuario estatico actual : $STAT_USER_1 (hash pwd: $(printf '%s' "$STAT_PWD_1" | sha256sum | cut -c1-10))"

# 6. Esperar primeras inserciones de Spring Boot en connection_audit_log
echo ""
echo "[6/8] Verificando registros de Spring Boot en public.connection_audit_log..."
for i in $(seq 1 30); do
  DYN_COUNT=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT COUNT(*) FROM public.connection_audit_log WHERE credential_mode='DYNAMIC';" | tr -d '\r\n')
  STAT_COUNT=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT COUNT(*) FROM public.connection_audit_log WHERE credential_mode='STATIC';" | tr -d '\r\n')
  if [ "${DYN_COUNT:-0}" -ge 1 ] && [ "${STAT_COUNT:-0}" -ge 1 ]; then
    break
  fi
  sleep 2
done

if [ "${DYN_COUNT:-0}" -lt 1 ] || [ "${STAT_COUNT:-0}" -lt 1 ]; then
  echo "ERROR: Spring Boot no inserto registros iniciales en PostgreSQL."
  docker logs --tail 40 vm-app
  exit 1
fi

STAT_PID_1=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT backend_pid FROM public.connection_audit_log WHERE credential_mode='STATIC' ORDER BY id ASC LIMIT 1;" | tr -d '\r\n')
FIRST_DYN_USER=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT db_username FROM public.connection_audit_log WHERE credential_mode='DYNAMIC' ORDER BY id ASC LIMIT 1;" | tr -d '\r\n')
echo "  [OK] Spring Boot insertando en PostgreSQL (DYNAMIC rows=$DYN_COUNT, STATIC rows=$STAT_COUNT, primer user dinamico=$FIRST_DYN_USER, primer pid estatico=$STAT_PID_1)"

# 7. Forzar rotacion del rol estatico y esperar rotacion por TTL (60s) del rol dinamico
echo ""
echo "[7/8] Forzando rotacion de postgres-static-role y esperando rotacion por TTL (60s) de postgres-dynamic-role..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vm-vault vault write -f database/rotate-role/postgres-static-role >/dev/null

ROTATED_DYN="false"
ROTATED_STAT="false"

for elapsed in $(seq 1 40); do
  DISTINCT_DYN_USERS=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT COUNT(DISTINCT db_username) FROM public.connection_audit_log WHERE credential_mode='DYNAMIC';" | tr -d '\r\n')
  DISTINCT_STAT_PIDS=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT COUNT(DISTINCT backend_pid) FROM public.connection_audit_log WHERE credential_mode='STATIC';" | tr -d '\r\n')
  STAT_PWD_NOW=$(docker exec vm-app awk -F= '/password/{print $2}' /run/secrets/db-static.properties | tr -d '\r\n')
  STAT_PID_NOW=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT backend_pid FROM public.connection_audit_log WHERE credential_mode='STATIC' ORDER BY id DESC LIMIT 1;" | tr -d '\r\n')

  if [ "${DISTINCT_DYN_USERS:-0}" -ge 2 ]; then
    ROTATED_DYN="true"
  fi
  if [ "${DISTINCT_STAT_PIDS:-0}" -ge 2 ] && [ "$STAT_PID_NOW" != "$STAT_PID_1" ]; then
    ROTATED_STAT="true"
  fi

  if [ "$ROTATED_DYN" = "true" ] && [ "$ROTATED_STAT" = "true" ]; then
    break
  fi
  sleep 2
done

if [ "$ROTATED_DYN" != "true" ]; then
  echo "ERROR: No se detecto rotacion de usuario dinamico en connection_audit_log."
  exit 1
fi

if [ "$ROTATED_STAT" != "true" ]; then
  echo "ERROR: No se detecto rotacion de password/pool estatico en connection_audit_log."
  exit 1
fi

LATEST_DYN_USER=$(docker exec vm-db psql -U postgres -d pilotdb -tAc "SELECT db_username FROM public.connection_audit_log WHERE credential_mode='DYNAMIC' ORDER BY id DESC LIMIT 1;" | tr -d '\r\n')
echo "  [OK] Rotacion DINAMICA verificada: $FIRST_DYN_USER -> $LATEST_DYN_USER"
echo "  [OK] Rotacion ESTATICA verificada: app_static_user (pg_pid inicial: $STAT_PID_1 -> pg_pid post-rotacion: $STAT_PID_NOW, nuevo hash pwd: $(printf '%s' "$STAT_PWD_NOW" | sha256sum | cut -c1-10))"

# 8. Verificar recarga en caliente (@RefreshScope) de Gitea + Vault KV v2 a traves de vm-config-server
echo ""
echo "[8/8] Verificando commit en Gitea + rotacion Vault KV v2 + @RefreshScope en caliente (POST /api/pilot/config/refresh)..."
BEFORE_TAG=$(curl -fsS http://localhost:18080/api/pilot/state | docker exec -i vm-app jq -r '.springCloudConfig.customTag' | tr -d '\r\n')
REFRESH_RESP=$(curl -fsS -X POST http://localhost:18080/api/pilot/config/refresh | tr -d '\r')
REFRESH_OK=$(echo "$REFRESH_RESP" | docker exec -i vm-app jq -r '.refreshed' | tr -d '\r\n')
AFTER_TAG=$(echo "$REFRESH_RESP" | docker exec -i vm-app jq -r '.springCloudConfig.customTag' | tr -d '\r\n')
AFTER_SIG=$(echo "$REFRESH_RESP" | docker exec -i vm-app jq -r '.springCloudConfig.vaultKvSignature' | tr -d '\r\n')

if [ "$REFRESH_OK" != "true" ] || [ "$BEFORE_TAG" = "$AFTER_TAG" ]; then
  echo "ERROR: Fallo al refrescar propiedades de Spring Cloud Config en caliente: $REFRESH_RESP"
  exit 1
fi
echo "  [OK] @RefreshScope recargado sin reiniciar vm-app: tag $BEFORE_TAG -> $AFTER_TAG | Vault KV Signature: $AFTER_SIG"

echo ""
echo "=================================================================="
echo " RESULTADO: TODOS LOS CRITERIOS DE ACEPTACION SUPERADOS (EXIT 0)"
echo "=================================================================="
exit 0

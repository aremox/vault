#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

echo "=================================================================="
echo " PILOTO HASHICORP VAULT + ANSIBLE + SPRING BOOT + POSTGRESQL"
echo " Verificacion extremo a extremo de negociacion y rotado de claves"
echo "=================================================================="

# 1. Verificar contenedores e IPs estaticas en 172.29.0.0/24
echo ""
echo "[1/7] Verificando los 4 contenedores tipo VM y sus IPs fijas..."
declare -A EXPECTED_IPS=(
  ["vm-vault"]="172.29.0.10"
  ["vm-db"]="172.29.0.20"
  ["vm-app"]="172.29.0.30"
  ["vm-ansible"]="172.29.0.40"
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

# 2. Verificar estado de HashiCorp Vault Server (Initialized, Sealed: false, Storage: file)
echo ""
echo "[2/7] Verificando estado de vm-vault (modo Server real con file storage)..."
VAULT_STATUS_JSON=$(docker exec vm-vault vault status -format=json | tr -d '\r')
INIT=$(echo "$VAULT_STATUS_JSON" | grep -o '"initialized": *true' || true)
SEALED=$(echo "$VAULT_STATUS_JSON" | grep -o '"sealed": *false' || true)
STORAGE=$(echo "$VAULT_STATUS_JSON" | grep -o '"storage_type": *"file"' || true)

if [ -z "$INIT" ] || [ -z "$SEALED" ] || [ -z "$STORAGE" ]; then
  echo "ERROR: Estado de Vault invalido: $VAULT_STATUS_JSON"
  exit 1
fi
echo "  [OK] Vault Server -> Initialized: true | Sealed: false | Storage Type: file"

# 3. Verificar aprovisionamiento Ansible por SSH (role_id + secret_id con permisos 0600)
echo ""
echo "[3/7] Verificando ejecucion del playbook Ansible (role_id + secret_id -> vm-app)..."
ANSIBLE_OUT=$(docker logs vm-ansible 2>&1 | tr -d '\r')
echo "$ANSIBLE_OUT" | tail -n 5
if ! echo "$ANSIBLE_OUT" | grep -q "failed=0"; then
  echo "Re-ejecutando playbook Ansible..."
  ANSIBLE_OUT=$(docker exec vm-ansible ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml | tr -d '\r')
  echo "$ANSIBLE_OUT" | tail -n 5
  if ! echo "$ANSIBLE_OUT" | grep -q "failed=0"; then
    echo "ERROR: Playbook de Ansible reporto fallos."
    exit 1
  fi
fi

ROLE_PERM=$(docker exec vm-app stat -c "%a" /etc/vault.d/role_id | tr -d '\r\n')
SECRET_PERM=$(docker exec vm-app stat -c "%a" /etc/vault.d/secret_id | tr -d '\r\n')
if [ "$ROLE_PERM" != "600" ] || [ "$SECRET_PERM" != "600" ]; then
  echo "ERROR: Permisos incorrectos en /etc/vault.d (role_id=$ROLE_PERM, secret_id=$SECRET_PERM)"
  exit 1
fi
echo "  [OK] /etc/vault.d/role_id ($ROLE_PERM) y /etc/vault.d/secret_id ($SECRET_PERM) aprovisionados via SSH"

# 4. Verificar ficheros renderizados por Vault Agent
echo ""
echo "[4/7] Verificando ficheros de secretos renderizados por vault-agent en vm-app..."
docker exec vm-app test -s /run/secrets/db-dynamic.properties
docker exec vm-app test -s /run/secrets/db-static.properties
DYN_USER_1=$(docker exec vm-app awk -F= '/username/{print $2}' /run/secrets/db-dynamic.properties | tr -d '\r\n')
STAT_USER_1=$(docker exec vm-app awk -F= '/username/{print $2}' /run/secrets/db-static.properties | tr -d '\r\n')
STAT_PWD_1=$(docker exec vm-app awk -F= '/password/{print $2}' /run/secrets/db-static.properties | tr -d '\r\n')
echo "  [OK] Usuario dinamico actual : $DYN_USER_1"
echo "  [OK] Usuario estatico actual : $STAT_USER_1 (hash pwd: $(printf '%s' "$STAT_PWD_1" | sha256sum | cut -c1-10))"

# 5. Esperar primeras inserciones de Spring Boot en connection_audit_log
echo ""
echo "[5/7] Verificando registros de Spring Boot en public.connection_audit_log..."
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

# 6. Forzar rotacion del rol estatico y esperar rotacion por TTL (60s) del rol dinamico
echo ""
echo "[6/7] Forzando rotacion de postgres-static-role y esperando rotacion por TTL (60s) de postgres-dynamic-role..."
ROOT_TOKEN=$(docker exec vm-vault cat /vault/bootstrap/root.token | tr -d '\r\n')
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

# 7. Mostrar evidencia en PostgreSQL y logs de Spring Boot
echo ""
echo "[7/7] Resumen de auditoria en PostgreSQL (public.connection_audit_log):"
docker exec vm-db psql -U postgres -d pilotdb -c "SELECT credential_mode, db_username, backend_pid, MIN(executed_at) AS first_seen, MAX(executed_at) AS last_seen, COUNT(*) AS probes FROM public.connection_audit_log GROUP BY credential_mode, db_username, backend_pid ORDER BY MIN(id);"

echo ""
echo "Sesiones activas en pg_stat_activity:"
docker exec vm-db psql -U postgres -d pilotdb -c "SELECT pid, usename, application_name, client_addr, state FROM pg_stat_activity WHERE datname='pilotdb' AND usename <> 'postgres';"

echo ""
echo "=================================================================="
echo " RESULTADO: TODOS LOS CRITERIOS DE ACEPTACION SUPERADOS (EXIT 0)"
echo "=================================================================="
exit 0

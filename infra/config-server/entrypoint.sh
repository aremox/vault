#!/bin/bash
set -e

mkdir -p /var/run/sshd /etc/vault.d /run/secrets /var/log/vault-agent

echo "[vm-config-server] Iniciando demonio OpenSSH Server (simulacion VM)..."
/usr/sbin/sshd

echo "[vm-config-server] Esperando aprovisionamiento de /etc/vault.d/role_id y /etc/vault.d/secret_id via Ansible..."
while [ ! -s /etc/vault.d/role_id ] || [ ! -s /etc/vault.d/secret_id ]; do
  sleep 2
done

if ! pgrep -x "vault" >/dev/null 2>&1; then
  echo "[vm-config-server] Arrancando demonio vault-agent..."
  vault agent -config=/etc/vault.d/vault-agent.hcl >/var/log/vault-agent/agent.log 2>&1 &
fi

echo "[vm-config-server] Esperando renderizado de /run/secrets/git-credentials.properties y /run/secrets/vault-token..."
while [ ! -s /run/secrets/git-credentials.properties ] || [ ! -s /run/secrets/vault-token ]; do
  if ! pgrep -x "vault" >/dev/null 2>&1; then
    vault agent -config=/etc/vault.d/vault-agent.hcl >/var/log/vault-agent/agent.log 2>&1 &
  fi
  sleep 1
done

echo "[vm-config-server] Esperando a que el repositorio Gitea (http://172.29.0.50:3000/pilot-admin/pilot-config.git) este disponible..."
until curl -sf http://172.29.0.50:3000/api/v1/repos/pilot-admin/pilot-config >/dev/null 2>&1; do
  sleep 1
done

export VAULT_TOKEN=$(tr -d '\r\n ' < /run/secrets/vault-token)
echo "[vm-config-server] Credenciales Gitea y Token Vault listos. Arrancando Spring Cloud Config Server en :8888..."

exec java -jar /opt/config-server/config-server.jar --vault.token="$VAULT_TOKEN"

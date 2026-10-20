#!/bin/bash
set -e

mkdir -p /var/run/sshd /etc/vault.d /run/secrets /var/log/vault-agent

echo "[vm-app] Iniciando demonio OpenSSH Server (simulacion VM)..."
/usr/sbin/sshd

echo "[vm-app] Esperando aprovisionamiento de /etc/vault.d/role_id y /etc/vault.d/secret_id via Ansible..."
while [ ! -s /etc/vault.d/role_id ] || [ ! -s /etc/vault.d/secret_id ]; do
  sleep 2
done

# Asegurar que vault-agent este corriendo (puede haber sido iniciado por Ansible o por este supervisor)
if ! pgrep -x "vault" >/dev/null 2>&1; then
  echo "[vm-app] Arrancando demonio vault-agent..."
  vault agent -config=/etc/vault.d/vault-agent.hcl >/var/log/vault-agent/agent.log 2>&1 &
fi

echo "[vm-app] Esperando renderizado de credenciales en /run/secrets/db-dynamic.properties y db-static.properties..."
while [ ! -s /run/secrets/db-dynamic.properties ] || [ ! -s /run/secrets/db-static.properties ]; do
  if ! pgrep -x "vault" >/dev/null 2>&1; then
    vault agent -config=/etc/vault.d/vault-agent.hcl >/var/log/vault-agent/agent.log 2>&1 &
  fi
  sleep 1
done

echo "[vm-app] Credenciales negociadas por Vault Agent disponibles en /run/secrets/."

echo "[vm-app] Esperando a que Spring Cloud Config Server (http://172.29.0.60:8888/vault-rotation-pilot/default) responda..."
for i in $(seq 1 30); do
  if curl -sf http://172.29.0.60:8888/vault-rotation-pilot/default >/dev/null 2>&1; then
    echo "[vm-app] Spring Cloud Config Server disponible en 172.29.0.60:8888."
    break
  fi
  sleep 1
done

if [ -f /opt/app/app.jar ]; then
  echo "[vm-app] Arrancando aplicacion Java Spring Boot (/opt/app/app.jar)..."
  exec java -jar /opt/app/app.jar
elif [ -f /opt/app-src/pom.xml ]; then
  echo "[vm-app] Compilando y ejecutando aplicacion Spring Boot desde /opt/app-src..."
  cd /opt/app-src
  mvn -q clean package -DskipTests
  cp target/*.jar /opt/app/app.jar
  exec java -jar /opt/app/app.jar
else
  echo "[vm-app] Jar de Spring Boot aun no presente; manteniendo contenedor VM activo..."
  tail -f /var/log/vault-agent/agent.log /dev/null
fi

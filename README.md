# Piloto HashiCorp Vault + Ansible + Spring Boot + PostgreSQL

Piloto sobre contenedores que simulan máquinas virtuales en la subred `172.29.0.0/24` para validar la negociación AppRole y la rotación automática y bajo demanda de credenciales de base de datos (Dinámicas y Estáticas) con recarga en caliente de pools `HikariCP` en Java 21 Spring Boot 3.

## Topología de Red (`172.29.0.0/24`)

- **`vm-vault` (`172.29.0.10`):** Servidor HashiCorp Vault 1.17 con almacenamiento persistente (`file`), auto-init/unseal y motor `database/` configurado con `postgres-dynamic-role` (TTL 60s) y `postgres-static-role` (rotación 60s).
- **`vm-db` (`172.29.0.20`):** PostgreSQL 16 (`pilotdb`) con tabla de auditoría `public.connection_audit_log`, superusuario `vault_admin` y usuario fijo `app_static_user`.
- **`vm-app` (`172.29.0.30`):** Contenedor tipo VM con `sshd`, `vault-agent` (AppRole + plantillas `.ctmpl`) y aplicación Java 21 Spring Boot 3 con consola web animada en `http://localhost:18080`.
- **`vm-ansible` (`172.29.0.40`):** Nodo de control Ansible que obtiene `role_id` y genera `secret_id` en Vault API y los despliega por SSH en `vm-app` (`/etc/vault.d/role_id` y `/etc/vault.d/secret_id` con permisos `0600`).

## Ejecución Rápida

```bash
# 1. Construir y levantar las 4 VMs
docker compose up -d --build

# 2. Abrir consola web animada
# http://localhost:18080

# 3. Ejecutar verificaciones automatizadas
bash scripts/verify-pilot.sh
bash scripts/verify-ui.sh
```

## Especificaciones (Spec-Driven)

- [SPEC 01 — Piloto de negociación y rotación de claves BBDD](specs/01-vault-rotacion-claves-bbdd.md) (`Implemented`)
- [SPEC 02 — Consola web animada de arquitectura y rotación en vivo](specs/02-web-animada-arquitectura-vault.md) (`Implemented`)

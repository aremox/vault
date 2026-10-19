# SPEC 01 — Piloto de negociación y rotación de claves entre Spring Boot y PostgreSQL con HashiCorp Vault y Ansible

> **Status:** Implemented
> **Depends on:** Ninguna
> **Date:** 2026-10-19
> **Objective:** Desplegar un piloto sobre contenedores que simulan máquinas virtuales donde Ansible aprovisiona credenciales AppRole y una aplicación Java Spring Boot negocia y rota automáticamente claves dinámicas y estáticas contra PostgreSQL mediante HashiCorp Vault Server y Vault Agent.

---

## Por qué existe esta spec

Antes de integrar HashiCorp Vault en entornos productivos basados en máquinas virtuales, es necesario validar de extremo a extremo el ciclo de vida de las credenciales de base de datos sin acoplar la aplicación al SDK de Vault ni requerir reinicios en cada rotación. Este piloto reproduce la topología de máquinas virtuales sobre contenedores con red IP estática, automatiza la entrega del par `role_id` y `secret_id` mediante Ansible por SSH, y verifica tanto roles dinámicos (usuarios efímeros por lease) como roles estáticos (rotación periódica de contraseña de un usuario fijo) en una aplicación Java Spring Boot conectada a PostgreSQL.

---

## Alcance

**Dentro del alcance:**

- Topología de 4 contenedores en `docker-compose.yml` simulando máquinas virtuales en la subred `172.29.0.0/24`: `vm-vault` (`172.29.0.10`), `vm-db` (`172.29.0.20`), `vm-app` (`172.29.0.30`) y `vm-ansible` (`172.29.0.40`).
- Servidor HashiCorp Vault en modo producción local con almacenamiento en disco (`file` backend), script de inicialización (`operator init`), desellado automático (`operator unseal`) y configuración de políticas, motor `database/` y método `auth/approle`.
- Base de datos PostgreSQL 16 en `vm-db` con esquema de prueba y configuración de dos roles en Vault:
  - Rol dinámico (`postgres-dynamic-role`) con creación y revocación de usuarios SQL efímeros y TTL corto (60s) para observar la rotación en vivo.
  - Rol estático (`postgres-static-role`) asociado al usuario fijo `app_static_user` con periodo de rotación automática de contraseña (60s).
- Playbook de Ansible en `vm-ansible` que consulta `vm-vault` para obtener el `role_id` y generar un `secret_id` de un solo uso (o TTL acotado), y los despliega por SSH en `vm-app` bajo `/etc/vault.d/role_id` y `/etc/vault.d/secret_id`.
- Demonio `vault-agent` en `vm-app` autenticado mediante AppRole (`auto_auth`), encargado de renovar leases y renderizar en disco los ficheros `/run/secrets/db-dynamic.properties` y `/run/secrets/db-static.properties`.
- Aplicación Java 21 con Spring Boot 3 en `vm-app` que consume ambos ficheros de propiedades, detecta cambios en caliente al rotar las credenciales, actualiza los pools de conexiones `HikariDataSource` sin reiniciar el proceso JVM y ejecuta consultas periódicas de verificación contra PostgreSQL.
- Script CLI de verificación (`scripts/verify-pilot.sh`) que valida la rotación automática y manual de ambos tipos de credenciales e inspecciona `pg_stat_activity` y la tabla de auditoría en PostgreSQL.

**Fuera del alcance (para futuras specs):**

- Clúster de alta disponibilidad (HA) de Vault con Raft multimodo o Consul.
- Desellado automático mediante KMS en nube pública (AWS KMS, Azure Key Vault, GCP Cloud KMS).
- Certificados TLS mutuos (mTLS) gestionados por una PKI externa al piloto.
- Interfaz gráfica web o dashboard frontend en la aplicación Spring Boot.
- Despliegue en Kubernetes (Helm / Vault Sidecar Injector).

---

## Modelo de datos

### 1. Tabla de auditoría y latidos en PostgreSQL (`infra/db/init.sql`)

```sql
CREATE TABLE IF NOT EXISTS public.connection_audit_log (
    id BIGSERIAL PRIMARY KEY,
    credential_mode VARCHAR(16) NOT NULL, -- 'DYNAMIC' | 'STATIC'
    db_username VARCHAR(128) NOT NULL,
    backend_pid INTEGER NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 2. Ficheros renderizados por Vault Agent en `vm-app` (`/run/secrets/`)

```properties
# /run/secrets/db-dynamic.properties
spring.datasource.dynamic.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb
spring.datasource.dynamic.username=v-approle-postgres-dyn-xxxx-1729350000
spring.datasource.dynamic.password=A9f#kL29zP0qW8xR1mN4
```

```properties
# /run/secrets/db-static.properties
spring.datasource.static.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb
spring.datasource.static.username=app_static_user
spring.datasource.static.password=R7v!mQ42pL9xK3wZ8nB1
```

### 3. Artefactos AppRole gestionados por Ansible en `vm-app` (`/etc/vault.d/`)

```text
/etc/vault.d/role_id     # UUID del rol AppRole (permisos 0600, propietario vault-app)
/etc/vault.d/secret_id   # UUID del secret_id emitido por Vault (permisos 0600, borrado por Vault Agent tras lectura si se configura remove_secret_id_file_after_reading)
```

---

## Plan de implementación

1. **Definir red e infraestructura base en `docker-compose.yml` y base de datos (`vm-db`).**
   Crear `docker-compose.yml` con la red bridge `vault-pilot-net` (`172.29.0.0/24`) y el servicio `vm-db` (PostgreSQL 16) junto con `infra/db/init.sql` que crea la base de datos `pilotdb`, la tabla `public.connection_audit_log`, el superusuario de administración para Vault (`vault_admin`) y el usuario fijo `app_static_user`.

2. **Configurar el nodo `vm-vault` en modo Server con inicialización y aprovisionamiento automático.**
   Crear `infra/vault/config.hcl` (storage `file` en `/vault/file`, listener TCP en `0.0.0.0:8200`), la política `infra/vault/policies/app-db-policy.hcl` y el script `infra/vault/scripts/bootstrap-vault.sh`. Este script ejecuta `vault operator init`, guarda las claves de unseal y root token en un volumen compartido seguro para aprovisionamiento, ejecuta `vault operator unseal`, habilita `database/`, configura `postgres-dynamic-role` (TTL `60s`, max TTL `120s`) y `postgres-static-role` (`rotation_period=60s`), y habilita `auth/approle` creando el rol `spring-app-role`.

3. **Construir la imagen del contenedor `vm-app` simulando una máquina virtual Linux.**
   Crear `infra/app-vm/Dockerfile`, `infra/app-vm/vault-agent.hcl`, las plantillas `infra/app-vm/templates/db-dynamic.properties.ctmpl` y `infra/app-vm/templates/db-static.properties.ctmpl`, y `infra/app-vm/entrypoint.sh`. El contenedor incluye `openssh-server` (para recibir a Ansible como en una VM real), el binario de `vault` (para ejecutar `vault agent`), y OpenJDK 21.

4. **Implementar el nodo `vm-ansible` y el playbook de distribución de `role_id` y `secret_id`.**
   Crear `infra/ansible/Dockerfile`, `infra/ansible/inventory.ini` (apuntando a `172.29.0.30` por SSH) y `infra/ansible/playbooks/deploy-approle.yml`. El playbook consulta la API de `vm-vault` (`172.29.0.10:8200`), extrae el `role_id` de `spring-app-role`, genera un nuevo `secret_id`, los copia por SSH a `/etc/vault.d/role_id` y `/etc/vault.d/secret_id` en `vm-app` con permisos `0600`, y arranca/recarga el servicio `vault-agent`.

5. **Desarrollar la aplicación Java Spring Boot con recarga en caliente de datasources.**
   Crear el proyecto Maven en `app/pom.xml`, `app/src/main/resources/application.yml` y las clases en `app/src/main/java/com/pilot/vault/`:
   - `VaultPilotApplication.java`: punto de entrada con `@EnableScheduling`.
   - `config/RotatableDataSourceManager.java`: gestiona dos instancias de `HikariDataSource` (`dynamicDataSource` y `staticDataSource`) y un `FileSystemWatcher` / verificador de hash sobre `/run/secrets/db-dynamic.properties` y `/run/secrets/db-static.properties` que realiza el cierre ordenado (`evict` / cierre del pool anterior) y recreación del pool al cambiar las credenciales en disco.
   - `service/DbRotationProbeService.java`: tarea programada cada 5 segundos que inserta un registro en `public.connection_audit_log` usando ambos datasources (`SELECT current_user, pg_backend_pid()`) e imprime en el log de consola el usuario activo y el resultado de la consulta.

6. **Crear el script de verificación y demostración extremo a extremo (`scripts/verify-pilot.sh`).**
   Escribir `scripts/verify-pilot.sh` para orquestar la prueba, mostrar los logs de negociación inicial, esperar/forzar una rotación de clave dinámica y una rotación de clave estática (`vault write -f database/rotate-role/postgres-static-role`), y consultar PostgreSQL demostrando el cambio de usuario efímero y de contraseña estática sin errores de conexión en Spring Boot.

---

## Criterios de aceptación

- [x] Al ejecutar `docker compose up -d --build`, los 4 contenedores (`vm-db`, `vm-vault`, `vm-app`, `vm-ansible`) arrancan y responden en sus IPs estáticas dentro de `172.29.0.0/24`.
- [x] `vault status` en `vm-vault` devuelve `Initialized: true` y `Sealed: false` usando almacenamiento en disco (`Storage Type: file`), no modo `-dev`.
- [x] El playbook `infra/ansible/playbooks/deploy-approle.yml` se ejecuta contra `vm-app` por SSH con `failed=0` y deposita `/etc/vault.d/role_id` y `/etc/vault.d/secret_id` con permisos `0600`.
- [x] `vault-agent` en `vm-app` se autentica con éxito vía AppRole y genera `/run/secrets/db-dynamic.properties` y `/run/secrets/db-static.properties` con credenciales válidas.
- [x] La aplicación Spring Boot inserta filas cada 5 segundos en `public.connection_audit_log` tanto para `credential_mode = 'DYNAMIC'` (con usuario `v-approle-postgres-dyn-...`) como para `credential_mode = 'STATIC'` (con usuario `app_static_user`).
- [x] Tras cumplirse el TTL de 60 segundos del secreto dinámico, `public.connection_audit_log` registra un nuevo `db_username` distinto al anterior para `credential_mode = 'DYNAMIC'` sin que la aplicación Spring Boot se reinicie ni pierda iteraciones.
- [x] Tras ejecutarse la rotación de contraseña de `postgres-static-role` (por periodo de 60s o mediante `vault write -f database/rotate-role/postgres-static-role`), `vault-agent` actualiza `/run/secrets/db-static.properties`, Spring Boot recarga su pool estático con la nueva contraseña y sigue insertando filas con `app_static_user` sin errores de autenticación SQL.
- [x] El script `scripts/verify-pilot.sh` termina con código de salida `0` tras comprobar automáticamente las rotaciones de ambos roles en base de datos.

---

## Decisiones

- **Sí:** Usar **Vault Agent + plantillas (`.ctmpl`)** en `vm-app` en lugar de `spring-cloud-starter-vault-config` directo contra la API de Vault. Desacopla la aplicación del servidor Vault, simula fielmente la arquitectura recomendada en máquinas virtuales y delega la gestión del token y los leases al agente local.
- **No:** Conectar Spring Boot directamente a la API HTTP de Vault con AppRole. Obliga a gestionar renovación de tokens y reintentos de red dentro del código de negocio de cada aplicación.
- **Sí:** Inyectar `role_id` y `secret_id` mediante **Ansible sobre SSH**. Reproduce el flujo real de aprovisionamiento de infraestructura sobre VMs (entrega del `secret_id` desde el orquestador de despliegue al host destino).
- **No:** Montar `role_id` y `secret_id` directamente como volúmenes compartidos desde el host en `docker-compose.yml` hacia `vm-app`. Ocultaría la fase de entrega segura y automatización que se quiere validar con Ansible.
- **Sí:** Probar **ambos modos de secretos de BBDD (Dinámicos y Estáticos)** con PostgreSQL. Permite comparar en el mismo piloto la creación/destrucción de usuarios efímeros frente a la rotación de password de cuentas legacy fijas.
- **No:** Ejecutar Vault en modo `-dev`. El modo `-dev` omite el ciclo real de `init`, `unseal` y persistencia en disco que existe en una máquina virtual real.
- **Sí:** Recarga programática de `HikariDataSource` al detectar cambios en los ficheros renderizados por Vault Agent. Por defecto, HikariCP mantiene conexiones abiertas aunque cambie la contraseña en el servidor PostgreSQL; recrear el pool al cambiar el fichero fuerza que las nuevas conexiones usen inmediatamente la nueva clave rotada.

---

## Riesgos

| Riesgo | Mitigación |
| ------ | ---------- |
| Conexiones existentes en el pool `HikariCP` estático siguen vivas en PostgreSQL tras rotar la contraseña de `app_static_user`, dando un falso positivo de rotación. | `RotatableDataSourceManager` cierra (`close()`) el `HikariDataSource` anterior y abre uno nuevo al detectar cambio en `db-static.properties`, forzando un nuevo handshake de autenticación SQL con la nueva contraseña y verificando que `pg_backend_pid()` cambia. |
| Condición de carrera entre la revocación del usuario dinámico en Vault y el renderizado del fichero por `vault-agent`. | Configurar en `vault-agent.hcl` la recarga antes de la expiración del lease y aplicar un cierre diferido (grace period de 5s) del pool `HikariDataSource` saliente mientras el nuevo pool ya está activo. |
| Ansible intenta aprovisionar `vm-app` antes de que `vm-vault` haya terminado el `init`, `unseal` y creación de roles. | El contenedor `vm-ansible` o el playbook incluye una tarea `uri` con `until` que espera a que `vm-vault` responda `initialized: true, sealed: false` y el endpoint AppRole esté listo. |

---

## Qué **no** incluye esta spec

- Alta disponibilidad de Vault (clúster Raft/Consul) ni auto-unseal con KMS cloud.
- Certificados TLS/mTLS entre contenedores.
- Dashboard web o interfaz gráfica (toda la verificación se realiza mediante `scripts/verify-pilot.sh`, logs y consultas SQL).
- Despliegue sobre hipervisores pesados (Vagrant/VirtualBox/QEMU) o Kubernetes.

Cada uno de esos puntos, si se aborda en el futuro, irá en su propia spec independiente.

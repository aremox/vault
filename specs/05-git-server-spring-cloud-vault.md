# Spec 05: Servidor Git Gitea + Spring Cloud Config Server + Integración con HashiCorp Vault

- **Status**: Approved
- **Depends on**: SPEC 01, SPEC 02, SPEC 03, SPEC 04
- **Date**: 2026-10-19
- **Objective**: Añadir al laboratorio un servidor Git ligero con interfaz web (`vm-git` con Gitea) y un servidor dedicado Spring Cloud Config (`vm-config-server`) integrado con HashiCorp Vault y Ansible para centralizar y refrescar en caliente (`@RefreshScope`) las propiedades y secretos de la aplicación Spring Boot (`vm-app`).

---

## 1. Scope

### Qué entra en el alcance (In Scope)
1. **Nueva Máquina 5 — `vm-git` (`172.29.0.50`, puerto Host `13000:3000`)**:
   - Contenedor basado en **Gitea** (`gitea/gitea:1.22-rootless` o Alpine con Gitea) configurado en modo ligero con SQLite3 embebido.
   - Script de auto-aprovisionamiento (`infra/git/bootstrap-gitea.sh`) que al arrancar:
     - Inicializa Gitea sin asistente manual (`INSTALL_LOCK=true`).
     - Crea el usuario administrador `pilot-admin` y genera un token/credencial de acceso.
     - Crea el repositorio privado `pilot-admin/pilot-config` y hace el commit inicial de `vault-rotation-pilot.yml` con propiedades de configuración de negocio y telemetría (`pilot.config.banner`, `pilot.config.environment`, `pilot.probe.custom-tag`, `pilot.config.version`).
2. **Integración de Seguridad en `vm-vault` (`172.29.0.10`) y `vm-ansible` (`172.29.0.40`)**:
   - En `infra/vault/scripts/bootstrap-vault.sh`:
     - Habilitar el motor de secretos **KV v2** en la ruta `secret/`.
     - Almacenar en `secret/data/git-credentials` las credenciales de conexión a Gitea (`git_username`, `git_password` / token) para que el Config Server no tenga contraseñas de Git hardcodeadas en su imagen.
     - Almacenar en `secret/data/vault-rotation-pilot` propiedades secretas de aplicación (`pilot.vault.kv.secret-signature`, `pilot.vault.kv.encryption-salt`) que Spring Cloud Config combinará con las propiedades del repositorio Git.
   - Ampliar la política ACL `infra/vault/policies/app-db-policy.hcl` (y/o política para `vm-config-server`) para permitir lectura de `secret/data/git-credentials` y `secret/data/vault-rotation-pilot`.
   - En `vm-ansible` (`infra/ansible/playbooks/deploy-approle.yml` e `inventory.ini`):
     - Aprovisionar también por SSH a `vm-config-server` (`172.29.0.60`) con su identidad AppRole (`role_id` + `secret_id`), para que su `vault-agent` local obtenga de Vault tanto el token como las credenciales de Gitea.
3. **Nueva Máquina 6 — `vm-config-server` (`172.29.0.60`, puerto Host `18888:8888`)**:
   - Contenedor que simula una VM dedicada para **Spring Cloud Config Server** (`config-server/pom.xml`, Java 21 + `spring-cloud-config-server` + `openssh-server` + `vault-agent`).
   - Configurado con **Composite Environment Repository (`git` + `vault`)**:
     - **Backend 1 (`git`)**: Clona y sirve los ficheros YAML del repositorio `http://172.29.0.50:3000/pilot-admin/pilot-config.git` usando las credenciales que `vault-agent` ha descargado desde `secret/data/git-credentials` de Vault.
     - **Backend 2 (`vault`)**: Lee secretos KV v2 directamente desde `http://172.29.0.10:8200` (`secret/data/vault-rotation-pilot`) usando el token renovado por `vault-agent`.
4. **Actualización de `vm-app` (`172.29.0.30`, puerto Host `18080:8080`) con Spring Cloud Config Client**:
   - Añadir `spring-cloud-starter-config` y `spring-boot-starter-actuator` a `app/pom.xml`.
   - Configurar `spring.config.import=optional:configserver:http://172.29.0.60:8888` en `app/src/main/resources/application.yml`.
   - Crear un bean `@RefreshScope` (`DynamicConfigPropertiesHolder.java` / `GitConfigControlService.java`) que exponga las propiedades traídas de Gitea y de Vault KV, y permita desde la API REST de la consola (`POST /api/pilot/config/update-and-refresh`):
     1. Hacer un nuevo commit en el repositorio `pilot-config` de Gitea vía su API HTTP (y/o actualizar el secreto en Vault KV).
     2. Invocar el `ContextRefresher.refresh()` de Spring Cloud en `vm-app` para recargar las propiedades en caliente sin reiniciar el contenedor ni cortar las conexiones a PostgreSQL.
5. **Actualización de la Consola Web Animada (`http://localhost:18080`) y Documentación**:
   - Añadir los nodos **`vm-git` (Gitea `:3000`)** y **`vm-config-server` (Spring Cloud Config `:8888`)** al mapa SVG animado con partículas que viajan en los eventos de lectura y refresh.
   - Añadir tarjeta interactiva **"Spring Cloud Config (Gitea + Vault KV)"** mostrando las propiedades actuales, el hash/mensaje del último commit en Gitea, enlace directo a `http://localhost:13000` y botón **"Commit en Gitea + Refresh Spring Cloud (@RefreshScope)"**.
   - Actualizar `scripts/verify-ui.sh` y `scripts/verify-pilot.sh` para validar extremo a extremo que un cambio en Gitea + Vault KV se propaga por `vm-config-server` hasta `vm-app` en caliente.
   - Actualizar `README.md`, `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md` con las 6 máquinas y los nuevos comandos paso a paso.

### Qué queda fuera del alcance (Out of Scope)
- Reemplazar la rotación actual de credenciales PostgreSQL con `vault-agent` (los canales `DYNAMIC` y `STATIC` de SPEC 01/02 se mantienen intactos y conviven con Spring Cloud Config).
- Clusters multi-nodo de Gitea o buses de mensajería externos como RabbitMQ/Kafka para Spring Cloud Bus (el refresh se dispara directamente vía HTTP REST / `ContextRefresher` para mantener el laboratorio ligero).

---

## 2. Data Model & Configuration Structures

### 2.1. Topología de Red Ampliada (`vault-pilot-net` — `172.29.0.0/24`)

| Máquina (Contenedor) | IP Interna | Puerto Host | Rol en la Arquitectura |
| :--- | :--- | :--- | :--- |
| `vm-vault` | `172.29.0.10` | `18200:8200` | HashiCorp Vault Server (Motores: `database/`, `secret/` KV v2, `auth/approle`) |
| `vm-db` | `172.29.0.20` | `15432:5432` | PostgreSQL 16 (`pilotdb`, tabla `connection_audit_log`) |
| `vm-app` | `172.29.0.30` | `18080:8080` | App Java 21 Spring Boot 3 + Spring Cloud Config Client (`@RefreshScope`) + Vault Agent |
| `vm-ansible` | `172.29.0.40` | — | Nodo de control Ansible (aprovisiona AppRole por SSH en `vm-config-server` y `vm-app`) |
| **`vm-git`** | **`172.29.0.50`** | **`13000:3000`** | **Servidor Git Gitea ligero con repositorio `pilot-admin/pilot-config.git`** |
| **`vm-config-server`** | **`172.29.0.60`** | **`18888:8888`** | **Spring Cloud Config Server (`@EnableConfigServer`) conectado a `vm-git` y `vm-vault`** |

### 2.2. Fichero en Gitea (`pilot-admin/pilot-config` -> `vault-rotation-pilot.yml`)
```yaml
pilot:
  config:
    environment: "production-lab"
    banner: "Configuracion centralizada desde Gitea + Spring Cloud Config"
    custom-tag: "git-v1"
    refresh-counter: 1
```

### 2.3. Secretos en Vault KV v2 (`secret/`)
1. **`secret/data/git-credentials`** (leído por `vault-agent` en `vm-config-server` para autenticar contra Gitea):
   ```json
   {
     "git_username": "pilot-admin",
     "git_password": "gitea_secret_password_2026"
   }
   ```
2. **`secret/data/vault-rotation-pilot`** (servido por `vm-config-server` a `vm-app` a través del backend compuesto de Vault):
   ```json
   {
     "pilot.vault.kv.secret-signature": "VAULT-KV-SIG-INITIAL-9001",
     "pilot.vault.kv.rotation-stage": "STAGE-1"
   }
   ```

### 2.4. Nuevos Campos en `GET /api/pilot/state` y Endpoint `POST /api/pilot/config/refresh`
`GET /api/pilot/state` incluirá un objeto `springCloudConfig`:
```json
{
  "configServerReachable": true,
  "giteaReachable": true,
  "giteaRepoUrl": "http://localhost:13000/pilot-admin/pilot-config",
  "environment": "production-lab",
  "banner": "Configuracion centralizada desde Gitea + Spring Cloud Config",
  "customTag": "git-v1",
  "vaultKvSignature": "VAULT-KV-SIG-INITIAL-9001",
  "lastCommitSha": "a1b2c3d",
  "refreshCount": 0,
  "lastRefreshedAt": "2026-10-19T21:35:00Z"
}
```
Y `POST /api/pilot/config/refresh` actualizará el YAML en Gitea (haciendo un commit nuevo vía API de Gitea) y el secreto KV en Vault, ejecutará `ContextRefresher.refresh()` en `vm-app` y devolverá las propiedades recién recargadas.

---

## 3. Implementation Plan

1. **Step 1 — Crear `vm-git` (Gitea ligero) y ampliar `vm-vault` + `vm-ansible`**:
   - Crear `infra/git/Dockerfile` y `infra/git/bootstrap-gitea.sh` para levantar Gitea en `172.29.0.50:3000` (Host `13000`), crear automáticamente el usuario `pilot-admin` y el repositorio `pilot-config` con `vault-rotation-pilot.yml`.
   - Actualizar `infra/vault/scripts/bootstrap-vault.sh` y `infra/vault/policies/app-db-policy.hcl` para habilitar `secret/` (KV v2) y poblar `secret/git-credentials` y `secret/vault-rotation-pilot`.
   - Actualizar `infra/ansible/inventory.ini` y `infra/ansible/playbooks/deploy-approle.yml` para aprovisionar AppRole por SSH tanto en `vm-config-server` como en `vm-app`.
2. **Step 2 — Crear el microservicio `vm-config-server` (Spring Cloud Config Server + Vault Agent)**:
   - Crear `config-server/pom.xml`, `config-server/src/main/java/com/pilot/configserver/ConfigServerApplication.java` y `config-server/src/main/resources/application.yml` con perfil compuesto `git,vault`.
   - Crear `infra/config-server/Dockerfile`, `entrypoint.sh`, `vault-agent.hcl` y plantilla `git-creds.properties.ctmpl` para que `vault-agent` obtenga de Vault el usuario/clave de Gitea y el token de Vault antes de iniciar el Config Server en el puerto `8888` (`18888` en Host).
   - Registrar `vm-git` y `vm-config-server` en `docker-compose.yml`.
3. **Step 3 — Integrar Spring Cloud Config Client y `@RefreshScope` en `vm-app` + Consola Web Animada**:
   - Actualizar `app/pom.xml` y `app/src/main/resources/application.yml` para importar propiedades desde `http://172.29.0.60:8888`.
   - Implementar `DynamicConfigProperties.java` (`@RefreshScope`), `SpringCloudConfigService.java` (que permite hacer commit en Gitea + rotar propiedad en Vault KV + ejecutar `ContextRefresher.refresh()`) y exponerlo en `PilotDashboardController.java` (`/api/pilot/state` y `POST /api/pilot/config/refresh`).
   - Actualizar `index.html`, `styles.css` y `app.js` para mostrar los 6 nodos en el mapa SVG animado (`vm-git` y `vm-config-server` incluidos) y la nueva tarjeta interactiva de **Spring Cloud Config + Gitea + Vault KV**.
4. **Step 4 — Actualizar Scripts de Verificación y Documentación Completa**:
   - Ampliar `scripts/verify-pilot.sh` y `scripts/verify-ui.sh` para verificar `vm-git`, `vm-config-server` y la recarga en caliente de propiedades vía `POST /api/pilot/config/refresh`.
   - Actualizar `README.md`, `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md` documentando la arquitectura de 6 máquinas y los nuevos comandos paso a paso.

---

## 4. Acceptance Criteria

- [ ] `docker compose ps` muestra los 6 contenedores (`vm-db`, `vm-vault`, `vm-git`, `vm-config-server`, `vm-app`, `vm-ansible`) en estado `healthy`.
- [ ] Gitea responde en `http://localhost:13000` con el repositorio `pilot-admin/pilot-config` y el fichero `vault-rotation-pilot.yml` creado automáticamente sin intervención manual.
- [ ] `vm-vault` tiene activo el motor KV v2 en `secret/` con `secret/git-credentials` y `secret/vault-rotation-pilot`.
- [ ] `vm-config-server` (`http://localhost:18888/vault-rotation-pilot/default`) devuelve combinadas las propiedades del repositorio Git de Gitea y los secretos de `secret/data/vault-rotation-pilot` de Vault.
- [ ] `vm-app` arranca consumiendo las propiedades de `vm-config-server` y al invocar `POST /api/pilot/config/refresh` (o pulsar el botón en la consola web) realiza un nuevo commit en Gitea, actualiza el secreto KV en Vault y recarga `@RefreshScope` en caliente cambiando los valores expuestos en `GET /api/pilot/state` sin reiniciar `vm-app`.
- [ ] La consola web en `http://localhost:18080` visualiza los 6 nodos en el diagrama SVG animado y permite disparar el refresh de Spring Cloud en un clic.
- [ ] `bash scripts/verify-ui.sh` y `bash scripts/verify-pilot.sh` terminan con `EXIT 0`.
- [ ] `README.md`, `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md` reflejan la nueva arquitectura y comandos 1 por 1.

---

## 5. Decisions Taken and Discarded

- **Gitea en contenedor propio (`vm-git`) frente a Git HTTP desnudo (Elegida 1B)**: Gitea sobre SQLite ofrece una interfaz web real en `http://localhost:13000` donde el usuario puede ver los commits y editar el YAML desde el navegador con un consumo de RAM muy contenido (~100 MB).
- **Contenedor dedicado `vm-config-server` frente a Config Server embebido en `vm-app` (Elegida 2B)**: Separar `vm-config-server` (`172.29.0.60:8888`) refleja fielmente la arquitectura empresarial real de microservicios con Spring Cloud, donde un servidor centralizado de configuración intermedia entre Git + Vault y las aplicaciones cliente.
- **Credenciales de Git protegidas en Vault + Composite Backend Git+Vault (Elegida 3A)**: Garantiza que ni siquiera `vm-config-server` tenga contraseñas de Git escritas en su imagen o código fuente, manteniendo la filosofía Zero-Trust de todo el laboratorio.

---

## 6. Identified Risks & Mitigations

- **Orden de arranque entre 6 contenedores**: `vm-config-server` necesita que `vm-git` haya creado ya el repositorio `pilot-config` y que `vm-ansible` le haya inyectado su AppRole antes de que `vm-app` le pida propiedades.
  - *Mitigación*: Healthchecks estrictos en `docker-compose.yml` (`vm-git` sano cuando el repo existe, `vm-ansible` aprovisiona tanto `vm-config-server` como `vm-app`, y `vm-app` usa `spring.config.import=optional:configserver:...` con reintento inicial hasta que `:8888` responda).

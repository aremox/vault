# 🛠️ Manual de Comandos 1 por 1 para Dummies: De Cero a las 6 VMs Montadas

> **¿Para quién es esta guía?**
> Si nunca has montado HashiCorp Vault, Gitea, Spring Cloud Config Server, Ansible, PostgreSQL y Spring Boot juntos y quieres **ir ejecutando los comandos 1 por 1 en orden cronológico sin dar absolutamente nada por supuesto**, estás en el sitio correcto.
>
> Cada comando de este manual tiene una **Ficha para Dummies** con 4 datos clave:
> 1. **📍 Dónde se ejecuta**: Para que nunca dudes en qué ventana o máquina tienes que escribirlo.
> 2. **💻 Comando exacto copiable**: Listo para copiar y pegar.
> 3. **🧠 ¿Qué hace este comando? (En cristiano)**: Explicación sencilla, sin tecnicismos oscuros.
> 4. **✅ Salida esperada**: Qué debe responder la pantalla para que sepas al 100% que todo ha salido bien antes de pasar al siguiente número.

---

## 🗺️ Índice Rápido: Elige tu Aventura

Este manual incluye **dos recorridos completos** para las **6 máquinas virtuales (`172.29.0.0/24`)**:

- **[Recorrido A — Modo Docker Paso a Paso (16 comandos desde tu PC)](#-recorrido-a--modo-docker-paso-a-paso-16-comandos-desde-tu-pc)**:
  Enciendes las 6 máquinas virtuales (`vm-db`, `vm-vault`, `vm-git`, `vm-config-server`, `vm-app`, `vm-ansible`) **una por una** desde la terminal de tu ordenador y compruebas que cada pieza funciona antes de encender la siguiente.
- **[Recorrido B — Modo Manual "Destripado" (Los 28 comandos internos 1 por 1)](#-recorrido-b--modo-manual-destripado-los-28-comandos-internos-1-por-1)**:
  Entras hasta la cocina de cada máquina virtual para ver y ejecutar **1 por 1** en orden cronológico real todos los comandos que construyen el sistema por dentro (crear usuarios en PostgreSQL, inicializar Gitea y su repositorio YAML, abrir la cámara acorazada de Vault, configurar motores `database/`, `secret/` KV v2 y `approle/`, repartir identidades por SSH con Ansible a `vm-config-server` y `vm-app`, levantar Spring Cloud Config y probar la rotación SQL y `@RefreshScope`).

---

## 🧭 Mapa Visual de los 28 Comandos Internos (Recorrido B)

En este diagrama puedes ver en qué orden cronológico exacto se ejecutan los **28 comandos internos** y qué máquina habla con cuál en cada fase:

```mermaid
sequenceDiagram
    autonumber
    participant DB as 🗄️ vm-db (PostgreSQL)<br/>172.29.0.20:5432
    participant GIT as 🦊 vm-git (Gitea)<br/>172.29.0.50:3000
    participant VAULT as 🔐 vm-vault (Vault Server)<br/>172.29.0.10:8200
    participant ANS as 🤖 vm-ansible (Ansible)<br/>172.29.0.40
    participant CFG as ☁️ vm-config-server<br/>172.29.0.60:8888
    participant APP as ☕ vm-app (Spring Boot)<br/>172.29.0.30:8080

    Note over DB: FASE 1: Preparar Base de Datos PostgreSQL (vm-db)
    DB->>DB: [Cmd 1] Crear superusuario vault_admin
    DB->>DB: [Cmd 2] Crear grupo pilot_app_group y app_static_user
    DB->>DB: [Cmd 3] Crear tabla connection_audit_log y dar permisos

    Note over GIT: FASE 2: Servidor Git Gitea y Repositorio YAML (vm-git)
    GIT->>GIT: [Cmd 4] Arrancar Gitea y crear usuario admin pilot-admin
    GIT->>GIT: [Cmd 5] Crear repo pilot-config y commit inicial vault-rotation-pilot.yml

    Note over VAULT: FASE 3: Encender, Inicializar y Desellar Vault (vm-vault)
    VAULT->>VAULT: [Cmd 6] Arrancar vault server (config.hcl)
    VAULT->>VAULT: [Cmd 7] Inicializar (vault operator init -> Unseal Key + Root Token)
    VAULT->>VAULT: [Cmd 8] Abrir puerta acorazada (vault operator unseal)
    VAULT->>VAULT: [Cmd 9] Login de administrador (export VAULT_TOKEN)

    Note over VAULT,DB: FASE 4: Motores Database, KV v2, Politicas y AppRole (vm-vault)
    VAULT->>VAULT: [Cmd 10] Activar motor database/
    VAULT->>DB: [Cmd 11] Conectar Vault a Postgres usando vault_admin
    VAULT->>VAULT: [Cmd 12] Crear Rol Dinamico (TTL 60s, usuarios efimeros)
    VAULT->>VAULT: [Cmd 13] Crear Rol Estatico (rotacion auto cada 60s)
    VAULT->>VAULT: [Cmd 14] Activar motor KV v2 en secret/
    VAULT->>VAULT: [Cmd 15] Guardar secret/git-credentials y secret/vault-rotation-pilot
    VAULT->>VAULT: [Cmd 16] Cargar politica ACL app-db-policy
    VAULT->>VAULT: [Cmd 17] Activar login de maquinas (auth enable approle)
    VAULT->>VAULT: [Cmd 18] Crear AppRole spring-app-role

    Note over ANS,APP: FASE 5: Ansible Reparte Identidad AppRole por SSH
    ANS->>VAULT: [Cmd 19] Pedir role_id publico por HTTP API
    ANS->>VAULT: [Cmd 20] Generar secret_id para vm-config-server y vm-app
    ANS->>CFG: [Cmd 21a] Inyectar role_id + secret_id por SSH (0600) en vm-config-server
    ANS->>APP: [Cmd 21b] Inyectar role_id + secret_id por SSH (0600) en vm-app

    Note over CFG,APP: FASE 6: Config Server, Vault Agent y App Java en Accion
    CFG->>VAULT: [Cmd 22] vault-agent en vm-config-server renderiza git-credentials.properties
    CFG->>GIT: [Cmd 23] Spring Cloud Config Server (:8888) fusiona Gitea YAML + Vault KV v2
    APP->>VAULT: [Cmd 24] vault-agent en vm-app renderiza db-dynamic y db-static.properties
    APP->>CFG: [Cmd 25] Arrancar app.jar (:8080) consumiendo Config Server y HikariCP

    Note over GIT,DB: FASE 7: Pruebas en Vivo de Rotacion SQL y @RefreshScope
    VAULT->>DB: [Cmd 26] Generar usuario dinamico SQL nuevo al vuelo
    VAULT->>DB: [Cmd 27] Forzar cambio inmediato de password del usuario estatico SQL
    APP->>GIT: [Cmd 28] Commit en Gitea + Rotar KV v2 + @RefreshScope en caliente
```

---

# 🚀 Recorrido A — Modo Docker Paso a Paso (16 Comandos desde tu PC)

En este recorrido vamos a levantar el laboratorio de **6 máquinas virtuales pieza por pieza** desde la carpeta del proyecto (`D:\Programacion\IA\vault`). Así verás cómo nace cada máquina en orden cronológico real en lugar de lanzarlo todo a ciegas.

> [!TIP]
> **¿Qué terminal uso en Windows?**
> Puedes abrir **Git Bash** o **PowerShell** en la carpeta `D:\Programacion\IA\vault`. Todos los comandos de abajo incluyen `MSYS_NO_PATHCONV=1` cuando se usa `docker exec` para que funcionen directamente en Git Bash sin que Windows cambie las barras `/` de las rutas.

---

### Paso A.1 — Comprobar que Docker está despierto

- **📍 Dónde se ejecuta**: En tu PC (`Host: Git Bash / PowerShell`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose version && docker info --format '{{.ServerVersion}}'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le pregunta a tu ordenador si tiene `docker compose` instalado y si el motor de Docker Desktop está encendido y respondiendo.
- **✅ Salida esperada**:
  ```text
  Docker Compose version v2.x.x
  27.x.x
  ```

---

### Paso A.2 — Limpiar cualquier montaje antiguo para empezar de cero

- **📍 Dónde se ejecuta**: En tu PC (`Host`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose down -v
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Apaga cualquier contenedor del piloto que hubiera quedado encendido de una prueba anterior y borra los discos temporales (`-v` = volúmenes). Es como "formatear la mesa de trabajo" para empezar 100% limpios.
- **✅ Salida esperada**:
  ```text
  [+] Running 11/11
   ✔ Container vm-ansible        Removed
   ✔ Container vm-app            Removed
   ✔ Container vm-config-server  Removed
   ✔ Container vm-git            Removed
   ✔ Container vm-vault          Removed
   ✔ Container vm-db             Removed
   ✔ Network vault-pilot-net     Removed
  ```

---

### Paso A.3 — Construir las imágenes de las máquinas virtuales

- **📍 Dónde se ejecuta**: En tu PC (`Host`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose build
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Lee los planos de construcción (`Dockerfile`) de `vm-git` (Gitea + SQLite3), `vm-config-server` (Spring Cloud Config Server + OpenSSH + Vault Agent), `vm-app` (Spring Boot 3 + Config Client + OpenSSH + Vault Agent) y `vm-ansible` (Ansible + cliente SSH).
- **✅ Salida esperada**:
  ```text
  [+] Building ... FINISHED
   ✔ Image vault-vm-git            Built
   ✔ Image vault-vm-config-server  Built
   ✔ Image vault-vm-app            Built
   ✔ Image vault-vm-ansible        Built
  ```

---

### Paso A.4 — Encender la Máquina 1: Base de Datos PostgreSQL (`vm-db` · `172.29.0.20`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d vm-db
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea la red privada `vault-pilot-net` (`172.29.0.0/24`) y enciende en segundo plano (`-d`) la primera máquina: PostgreSQL 16 (`vm-db`, IP `172.29.0.20`, puerto Host `15432`). Al arrancar ejecuta automáticamente `infra/db/init.sql`.
- **✅ Salida esperada**:
  ```text
  [+] Running 2/2
   ✔ Network vault-pilot-net  Created
   ✔ Container vm-db          Started
  ```

---

### Paso A.5 — Comprobar que PostgreSQL está sano y tiene los usuarios y tabla creados

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "\du" -c "\dt"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Entra en `vm-db` y verifica que existen los roles `vault_admin`, `pilot_app_group`, `app_static_user` y la tabla de auditoría `public.connection_audit_log`.
- **✅ Salida esperada**:
  ```text
                                      List of roles
      Role name    |                         Attributes                         
  -----------------+------------------------------------------------------------
   app_static_user | Member of {pilot_app_group}
   pilot_app_group | Cannot login
   postgres        | Superuser, Create role, Create DB, Replication, Bypass RLS
   vault_admin     | Superuser, Create role
  
                   List of relations
   Schema |         Name         | Type  |  Owner   
  --------+----------------------+-------+----------
   public | connection_audit_log | table | postgres
  ```

---

### Paso A.6 — Encender la Máquina 2: Servidor HashiCorp Vault (`vm-vault` · `172.29.0.10`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d vm-vault
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende `vm-vault` (`172.29.0.10`, puerto Host `18200`). Ejecuta `bootstrap-vault.sh` que inicializa Vault, lo desella (`Sealed: false`), configura los roles SQL en `database/`, activa el motor **KV v2 (`secret/`)** guardando `secret/git-credentials` y `secret/vault-rotation-pilot`, y crea el AppRole `spring-app-role`.
- **✅ Salida esperada**:
  ```text
  [+] Running 1/1
   ✔ Container vm-vault  Started
  ```

---

### Paso A.7 — Comprobar que Vault está abierto (`Sealed: false`) y tiene los secretos KV v2 cargados

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'vault status && export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault kv get secret/git-credentials && vault kv get secret/vault-rotation-pilot'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba que la cámara acorazada está abierta (`Sealed: false`) y que ya están guardados en `secret/` tanto el usuario/clave de Gitea como la firma secreta `VAULT-KV-SIG-INITIAL-9001` para Spring Cloud Config.
- **✅ Salida esperada**:
  ```text
  Initialized     true
  Sealed          false
  Storage Type    file
  ...
  git_username    pilot-admin
  pilot.vault.kv.secret-signature    VAULT-KV-SIG-INITIAL-9001
  ```

---

### Paso A.8 — Encender la Máquina 3: Servidor Git Gitea (`vm-git` · `172.29.0.50`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d vm-git
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende el servidor Git ligero **Gitea** (`vm-git`, IP `172.29.0.50`, puerto Host `13000`). Su script `bootstrap-gitea.sh` crea automáticamente el usuario administrador `pilot-admin`, el repositorio `pilot-admin/pilot-config` y hace el commit inicial de `vault-rotation-pilot.yml`.
- **✅ Salida esperada**:
  ```text
  [+] Running 1/1
   ✔ Container vm-git  Started
  ```

---

### Paso A.9 — Verificar que el repositorio `pilot-admin/pilot-config` responde en Gitea (`http://localhost:13000`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -u pilot-admin:gitea_secret_password_2026 http://localhost:13000/api/v1/repos/pilot-admin/pilot-config/contents/vault-rotation-pilot.yml
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Pregunta a la API de Gitea por el fichero `vault-rotation-pilot.yml`. También puedes abrir `http://localhost:13000/pilot-admin/pilot-config` en tu navegador.
- **✅ Salida esperada**:
  Un JSON con `"name":"vault-rotation-pilot.yml"`, `"path":"vault-rotation-pilot.yml"` y el `"sha"` del commit inicial.

---

### Paso A.10 — Encender la Máquina 4: Spring Cloud Config Server (`vm-config-server` · `172.29.0.60`) en espera de AppRole

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d --no-deps vm-config-server
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende `vm-config-server` (`172.29.0.60`, puerto Host `18888`) sin lanzar todavía Ansible. Arranca su demonio SSH (`sshd`) y se queda esperando a que Ansible le entregue su identidad AppRole para poder pedir a Vault la contraseña de Gitea.
- **✅ Salida esperada**:
  ```text
  [+] Running 1/1
   ✔ Container vm-config-server  Started
  ```

---

### Paso A.11 — Encender la Máquina 5: Aplicación Spring Boot (`vm-app` · `172.29.0.30`) en espera de AppRole

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d --no-deps vm-app
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende `vm-app` (`172.29.0.30`, puerto Host `18080`). Igual que la máquina anterior, arranca `sshd` y espera en `/etc/vault.d/` su `role_id` y `secret_id`.
- **✅ Salida esperada**:
  ```text
  [+] Running 1/1
   ✔ Container vm-app  Started
  ```

---

### Paso A.12 — Ejecutar la Máquina 6 (`vm-ansible` · `172.29.0.40`) para aprovisionar por SSH a `vm-config-server` y `vm-app`

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d vm-ansible && docker logs -f vm-ansible
  ```
  *(Pulsa `Ctrl+C` cuando veas el `PLAY RECAP` con `failed=0`).*
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende el nodo de control Ansible (`vm-ansible`, IP `172.29.0.40`), que ejecuta el playbook `deploy-approle.yml`:
  1. Pide el `role_id` a Vault y genera un `secret_id` distinto para cada máquina.
  2. Entra por SSH en **`vm-config-server` (`172.29.0.60`)**, escribe `/etc/vault.d/role_id` y `secret_id` (`0600`), arranca su `vault-agent` y espera a que exista `/run/secrets/git-credentials.properties`.
  3. Entra por SSH en **`vm-app` (`172.29.0.30`)**, escribe `/etc/vault.d/role_id` y `secret_id` (`0600`), arranca su `vault-agent` y espera a que existan `/run/secrets/db-dynamic.properties` y `db-static.properties`.
- **✅ Salida esperada**:
  ```text
  PLAY RECAP *********************************************************************
  vm-app                     : ok=12   changed=4    unreachable=0    failed=0
  vm-config-server           : ok=12   changed=4    unreachable=0    failed=0
  ```

---

### Paso A.13 — Comprobar que `vm-config-server` (`http://localhost:18888`) sirve la configuración combinada de Gitea + Vault KV v2

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s http://localhost:18888/vault-rotation-pilot/default
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Consulta el endpoint de **Spring Cloud Config Server**. Comprobarás que devuelve combinados los dos `propertySources`: las propiedades secretas de **Vault KV v2** (`pilot.vault.kv.secret-signature`) y las propiedades del fichero YAML de **Gitea** (`pilot.config.banner`, `pilot.config.custom-tag`).
- **✅ Salida esperada**:
  Un JSON con `"name":"vault-rotation-pilot"` y los dos orígenes (`vault:vault-rotation-pilot` y `http://172.29.0.50:3000/pilot-admin/pilot-config.git`).

---

### Paso A.14 — Comprobar las contraseñas SQL generadas por Vault Agent en `vm-app`

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-app sh -c 'cat /run/secrets/db-dynamic.properties && echo "---" && cat /run/secrets/db-static.properties'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Muestra los dos ficheros que `vault-agent` ha renderizado en memoria RAM (`/run/secrets/`) dentro de `vm-app`: el usuario efímero dinámico (`v-approle-postgres-...`) y el usuario fijo estático (`app_static_user`).
- **✅ Salida esperada**:
  ```ini
  spring.datasource.dynamic.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb
  spring.datasource.dynamic.username=v-approle-postgres-...
  spring.datasource.dynamic.password=...
  ---
  spring.datasource.static.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb
  spring.datasource.static.username=app_static_user
  spring.datasource.static.password=...
  ```

---

### Paso A.15 — Comprobar que `vm-app` responde en `http://localhost:18080/api/pilot/state` y abrir la Consola Web Animada

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s http://localhost:18080/api/pilot/state
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Llama al endpoint principal de `vm-app`. Devuelve el JSON en tiempo real con el estado de las **6 VMs**, los artefactos AppRole, las credenciales dinámicas/estáticas, el bloque `springCloudConfig` (con los valores traídos de Gitea y Vault KV v2) y las sesiones activas en PostgreSQL.
- **✅ Salida esperada**:
  Un JSON que incluye `"nodes"`, `"credentials"` y `"springCloudConfig":{"configServerReachable":true,"giteaReachable":true,"customTag":"git-v1",...}`.
  🎉 **¡Ya puedes abrir [`http://localhost:18080`](http://localhost:18080) en tu navegador!**

---

### Paso A.16 — Pasar las dos suites automáticas de verificación (`verify-ui.sh` y `verify-pilot.sh`)

- **📍 Dónde se ejecuta**: En tu PC (`Host` con Git Bash).
- **💻 Comando exacto copiable**:
  ```bash
  bash scripts/verify-ui.sh && bash scripts/verify-pilot.sh
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Ejecuta las dos verificaciones extremo a extremo:
  1. `verify-ui.sh`: verifica el mapa SVG de 6 nodos, fuerza rotación estática, rotación dinámica y un commit en Gitea + rotación KV v2 + `@RefreshScope` vía `POST /api/pilot/config/refresh`.
  2. `verify-pilot.sh`: verifica las 6 IPs en `172.29.0.0/24`, Vault, Gitea, Config Server, Ansible SSH en ambas VMs, la rotación automática por TTL en PostgreSQL y la recarga `@RefreshScope`.
- **✅ Salida esperada**:
  ```text
  ==================================================================
   RESULTADO: CONSOLA WEB Y ENDPOINTS VERIFICADOS CON EXITO (EXIT 0)
  ==================================================================
  ...
  ==================================================================
   RESULTADO: TODOS LOS CRITERIOS DE ACEPTACION SUPERADOS (EXIT 0)
  ==================================================================
  ```

---

# 🔬 Recorrido B — Modo Manual "Destripado" (Los 28 Comandos Internos 1 por 1)

¿Quieres saber **exactamente qué comandos se ejecutan por dentro** de cada una de las **6 máquinas virtuales** sin que ningún script lo haga por ti, o quieres ir lanzándolos tú mismo uno detrás de otro para practicar?

Aquí tienes la lista íntegra de los **28 comandos reales**, en orden cronológico estricto.

---

## 🗄️ Fase 1: Preparar la Base de Datos en `vm-db` (`172.29.0.20` · PostgreSQL 16)

Antes de que Vault pueda gestionar permisos o rotar contraseñas en PostgreSQL, necesitamos crear el superusuario de Vault, el grupo de la aplicación, el usuario fijo y la tabla de auditoría.

---

### Comando 1 — Crear el superusuario `vault_admin` para que Vault mande en PostgreSQL

- **📍 Dónde se ejecuta**: Dentro de `vm-db` (lanzado desde tu PC con `docker exec`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'vault_admin') THEN CREATE ROLE vault_admin WITH LOGIN SUPERUSER CREATEROLE PASSWORD 'vault_admin_pwd'; END IF; END \$\$;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea en PostgreSQL el usuario `vault_admin` con permiso `CREATEROLE`. Esta cuenta solo la usará HashiCorp Vault para fabricar usuarios efímeros cada 60 segundos y rotar contraseñas.
- **✅ Salida esperada**:
  ```text
  DO
  ```

---

### Comando 2 — Crear el grupo de permisos `pilot_app_group` y el usuario fijo `app_static_user`

- **📍 Dónde se ejecuta**: Dentro de `vm-db`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'pilot_app_group') THEN CREATE ROLE pilot_app_group NOLOGIN; END IF; IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_static_user') THEN CREATE ROLE app_static_user WITH LOGIN PASSWORD 'initial_static_pwd' IN ROLE pilot_app_group; END IF; END \$\$;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea el grupo `pilot_app_group` (del que heredarán permisos todos los usuarios efímeros) y el usuario fijo `app_static_user` (cuya contraseña rotará Vault cada 60 segundos).
- **✅ Salida esperada**:
  ```text
  DO
  ```

---

### Comando 3 — Crear la tabla `connection_audit_log` y dar permisos al grupo de la App

- **📍 Dónde se ejecuta**: Dentro de `vm-db`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "CREATE TABLE IF NOT EXISTS public.connection_audit_log (id BIGSERIAL PRIMARY KEY, credential_mode VARCHAR(16) NOT NULL, db_username VARCHAR(128) NOT NULL, backend_pid INTEGER NOT NULL, executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()); GRANT CONNECT ON DATABASE pilotdb TO pilot_app_group; GRANT USAGE ON SCHEMA public TO pilot_app_group; GRANT SELECT, INSERT ON public.connection_audit_log TO pilot_app_group; GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pilot_app_group;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea la tabla de auditoría donde `vm-app` insertará un latido cada 5 segundos por cada canal (`DYNAMIC` y `STATIC`) y concede permisos `SELECT, INSERT` a `pilot_app_group`.
- **✅ Salida esperada**:
  ```text
  CREATE TABLE
  GRANT
  GRANT
  GRANT
  GRANT
  ```

---

## 🦊 Fase 2: Inicializar el Servidor Git Gitea y el Repositorio YAML en `vm-git` (`172.29.0.50`)

En la máquina 5 (`vm-git`) corre un servidor Git **Gitea** con base de datos SQLite3 embebida donde vive la configuración centralizada de negocio (`vault-rotation-pilot.yml`).

---

### Comando 4 — Verificar el servidor Gitea y el usuario administrador `pilot-admin` en `vm-git`

- **📍 Dónde se ejecuta**: Dentro de `vm-git`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-git sh -c 'su-exec gitea gitea admin user list --config /data/gitea/conf/app.ini --custom-path /data/gitea --work-path /data/gitea'
  ```
  *(Nota: el comando que crea el usuario al arrancar es `su-exec gitea gitea admin user create --username pilot-admin --password gitea_secret_password_2026 --email pilot-admin@vault-pilot.local --admin --must-change-password=false`).*
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Lista los usuarios registrados dentro de Gitea sin necesidad de pasar por ningún asistente web manual (`INSTALL_LOCK = true`), confirmando que existe el administrador `pilot-admin`.
- **✅ Salida esperada**:
  ```text
  ID   Username     Email                         IsActive IsAdmin
  1    pilot-admin  pilot-admin@vault-pilot.local true     true
  ```

---

### Comando 5 — Verificar el repositorio `pilot-admin/pilot-config` y el fichero `vault-rotation-pilot.yml` en Gitea

- **📍 Dónde se ejecuta**: Contra la API HTTP de `vm-git` (`http://localhost:13000`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -u pilot-admin:gitea_secret_password_2026 http://localhost:13000/api/v1/repos/pilot-admin/pilot-config/contents/vault-rotation-pilot.yml
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba que el repositorio `pilot-admin/pilot-config` tiene subido en la rama `main` el archivo `vault-rotation-pilot.yml` que leerá Spring Cloud Config Server.
- **✅ Salida esperada**:
  Un JSON con `"name":"vault-rotation-pilot.yml"`, `"type":"file"` y su contenido codificado en Base64.

---

## 🔐 Fase 3: Encender, Inicializar y Abrir la Cámara Acorazada en `vm-vault` (`172.29.0.10`)

Cuando HashiCorp Vault arranca por primera vez, su almacenamiento en disco (`/vault/file`) está sin inicializar y sellado (`Sealed: true`). Estos 4 comandos abren la cámara acorazada.

---

### Comando 6 — Verificar el proceso del servidor Vault y su configuración (`config.hcl`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c "ps aux | grep 'vault server' && cat /vault/config/config.hcl"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba que `vault server -config=/vault/config/config.hcl` está corriendo en el puerto `8200` con almacenamiento persistente en `/vault/file`.
- **✅ Salida esperada**:
  ```hcl
  storage "file" {
    path = "/vault/file"
  }
  listener "tcp" {
    address     = "0.0.0.0:8200"
    tls_disable = 1
  }
  ui = true
  disable_mlock = true
  ```

---

### Comando 7 — Inicializar Vault por primera vez (`vault operator init`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'if [ ! -f /vault/bootstrap/init.json ]; then vault operator init -key-shares=1 -key-threshold=1 -format=json > /vault/bootstrap/init.json; fi && cat /vault/bootstrap/init.json'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Genera la llave maestra de cifrado de Vault y devuelve en JSON la `unseal_keys_b64` (llave para abrir la puerta acorazada) y el `root_token` (pase de superadministrador inicial).
- **✅ Salida esperada**:
  ```json
  {
    "unseal_keys_b64": ["..."],
    "root_token": "hvs...."
  }
  ```

---

### Comando 8 — Desellar la puerta acorazada (`vault operator unseal`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'vault operator unseal $(cat /vault/bootstrap/unseal.key)'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Introduce la llave `unseal.key` en Vault para que pase a estado `Sealed: false` (abierto y listo para operar).
- **✅ Salida esperada**:
  ```text
  Initialized     true
  Sealed          false
  ```

---

### Comando 9 — Autenticarse como Administrador (`VAULT_TOKEN` + `vault token lookup`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault token lookup'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Verifica que nuestro `root.token` está activo y tiene la política `[root]` para configurar los motores de secretos en la Fase 4.
- **✅ Salida esperada**:
  ```text
  display_name        root
  policies            [root]
  ```

---

## ⚙️ Fase 4: Configurar Motores `database/`, `secret/` (KV v2), Políticas y AppRole en `vm-vault`

Con Vault abierto, configuramos los dos motores de secretos (`database/` para PostgreSQL y `secret/` KV v2 para Gitea + Spring Cloud Config), la política de mínimo privilegio y la identidad AppRole.

---

### Comando 10 — Activar el motor de secretos de Bases de Datos (`vault secrets enable database`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && (vault secrets list | grep -q "^database/" || vault secrets enable database) && vault secrets list'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Habilita el motor `database/` en Vault para gestionar conexiones y credenciales dinámicas/estáticas contra bases de datos SQL.
- **✅ Salida esperada**:
  ```text
  database/     database     database_xxxx
  ```

---

### Comando 11 — Conectar Vault con PostgreSQL (`database/config/postgres-pilot`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write database/config/postgres-pilot plugin_name=postgresql-database-plugin allowed_roles="postgres-dynamic-role,postgres-static-role" connection_url="postgresql://{{username}}:{{password}}@172.29.0.20:5432/pilotdb?sslmode=disable" username="vault_admin" password="vault_admin_pwd"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Configura la conexión de Vault hacia `vm-db` (`172.29.0.20:5432/pilotdb`) usando el superusuario `vault_admin` creado en el Comando 1.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: database/config/postgres-pilot
  ```

---

### Comando 12 — Crear el Rol Dinámico con caducidad de 60 segundos (`postgres-dynamic-role`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write database/roles/postgres-dynamic-role db_name=postgres-pilot creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '\''{{password}}'\'' VALID UNTIL '\''{{expiration}}'\'' IN ROLE pilot_app_group;" revocation_statements="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '\''{{name}}'\''; DROP ROLE IF EXISTS \"{{name}}\";" default_ttl="60s" max_ttl="120s"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Define las sentencias SQL `CREATE ROLE` y `DROP ROLE` con las que Vault creará y destruirá usuarios efímeros cada 60 segundos.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: database/roles/postgres-dynamic-role
  ```

---

### Comando 13 — Crear el Rol Estático con rotación cada 60 segundos (`postgres-static-role`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write database/static-roles/postgres-static-role db_name=postgres-pilot username="app_static_user" rotation_statements="ALTER USER \"{{name}}\" WITH PASSWORD '\''{{password}}'\'';" rotation_period="60s"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le dice a Vault que tome el control del usuario fijo `app_static_user` y ejecute `ALTER USER ... WITH PASSWORD` automáticamente cada 60 segundos.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: database/static-roles/postgres-static-role
  ```

---

### Comando 14 — Activar el motor de secretos KV v2 en la ruta `secret/`

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && (vault secrets list | grep -q "^secret/" || vault secrets enable -version=2 -path=secret kv) && vault secrets list'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Activa el almacén de secretos Clave-Valor con control de versiones (**KV v2**) en la ruta `secret/`, necesario para guardar las credenciales de Gitea y los secretos que servirá Spring Cloud Config Server.
- **✅ Salida esperada**:
  ```text
  secret/       kv           kv_xxxx               n/a
  ```

---

### Comando 15 — Guardar en Vault KV v2 las credenciales de Gitea (`secret/git-credentials`) y los secretos de la App (`secret/vault-rotation-pilot`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault kv put secret/git-credentials git_username="pilot-admin" git_password="gitea_secret_password_2026" && vault kv put secret/vault-rotation-pilot "pilot.vault.kv.secret-signature=VAULT-KV-SIG-INITIAL-9001" "pilot.vault.kv.rotation-stage=STAGE-1" "pilot.vault.kv.encryption-salt=SALT-LAB-2026-INIT"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Guarda dos secretos clave en Vault:
  1. `secret/git-credentials`: usuario y contraseña de Gitea para que `vm-config-server` los obtenga vía `vault-agent` sin contraseñas hardcodeadas.
  2. `secret/vault-rotation-pilot`: propiedades secretas (`secret-signature`, `rotation-stage`, `encryption-salt`) que `vm-config-server` combinará con el YAML de Gitea.
- **✅ Salida esperada**:
  ```text
  ======= Secret Path =======
  secret/data/vault-rotation-pilot
  ======= Metadata =======
  Key                Value
  ---                -----
  version            1
  ```

---

### Comando 16 — Cargar la Política ACL de Seguridad (`app-db-policy`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault policy write app-db-policy /vault/policies/app-db-policy.hcl && vault policy read app-db-policy'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Carga en Vault el archivo `app-db-policy.hcl`, que autoriza a leer las credenciales dinámicas/estáticas de `database/` y los secretos KV v2 `secret/data/git-credentials` y `secret/data/vault-rotation-pilot`.
- **✅ Salida esperada**:
  ```text
  Success! Uploaded policy: app-db-policy
  ```

---

### Comando 17 — Activar el método de autenticación AppRole (`vault auth enable approle`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && (vault auth list | grep -q "^approle/" || vault auth enable approle) && vault auth list'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Activa el método de login para máquinas `approle/` en Vault.
- **✅ Salida esperada**:
  ```text
  approle/    approle    auth_approle_xxxx
  ```

---

### Comando 18 — Crear el perfil AppRole (`spring-app-role`) vinculado a `app-db-policy`

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write auth/approle/role/spring-app-role token_policies="app-db-policy" token_ttl="10m" token_max_ttl="30m" secret_id_ttl="10m" secret_id_num_uses=0'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea el rol `spring-app-role` con el que se autenticarán los `vault-agent` de `vm-config-server` y `vm-app`.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: auth/approle/role/spring-app-role
  ```

---

## 🤖 Fase 5: Negociar y Entregar `role_id` + `secret_id` con Ansible (`vm-ansible` -> `vm-config-server` y `vm-app`)

Ahora `vm-ansible` (`172.29.0.40`) obtiene de Vault el `role_id` y genera `secret_id` nuevos para inyectarlos por SSH en `vm-config-server` (`172.29.0.60`) y `vm-app` (`172.29.0.30`).

---

### Comando 19 — Pedir a Vault el identificador `role_id` del AppRole

- **📍 Dónde se ejecuta**: Contra la API de Vault (`vm-vault`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault read -field=role_id auth/approle/role/spring-app-role/role-id && echo ""'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Obtiene el UUID público (`role_id`) del perfil `spring-app-role`.
- **✅ Salida esperada**:
  ```text
  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  ```

---

### Comando 20 — Generar un pase secreto nuevo `secret_id` en Vault

- **📍 Dónde se ejecuta**: Contra la API de Vault (`vm-vault`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write -f -field=secret_id auth/approle/role/spring-app-role/secret-id && echo ""'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Genera un UUID secreto (`secret_id`) nuevo para autenticarse con `spring-app-role`.
- **✅ Salida esperada**:
  ```text
  yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
  ```

---

### Comando 21 — Ejecutar el Playbook de Ansible que inyecta `role_id` y `secret_id` por SSH en `vm-config-server` y `vm-app`

- **📍 Dónde se ejecuta**: Dentro de `vm-ansible`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-ansible ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Recorre las dos máquinas del inventario (`vm-config-server` en `172.29.0.60` y `vm-app` en `172.29.0.30`), les copia por SSH `/etc/vault.d/role_id` y `/etc/vault.d/secret_id` con permisos `0600`, arranca `vault agent` en ambas y verifica que se rendericen los ficheros en `/run/secrets/`.
- **✅ Salida esperada**:
  ```text
  PLAY RECAP *********************************************************************
  vm-app                     : ok=12   changed=4    unreachable=0    failed=0
  vm-config-server           : ok=12   changed=4    unreachable=0    failed=0
  ```

---

## ☁️☕ Fase 6: Spring Cloud Config Server (`vm-config-server`) y Aplicación Spring Boot (`vm-app`)

Con ambas máquinas aprovisionadas por Ansible, verificamos sus demonios `vault-agent` y sus procesos Java 21.

---

### Comando 22 — Verificar `vault-agent` y el fichero `/run/secrets/git-credentials.properties` en `vm-config-server`

- **📍 Dónde se ejecuta**: Dentro de `vm-config-server`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-config-server sh -c 'cat /run/secrets/git-credentials.properties && tail -n 6 /var/log/vault-agent/agent.log'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba que el `vault-agent` de `vm-config-server` se ha autenticado ante Vault y ha rellenado la plantilla `git-creds.properties.ctmpl` con el usuario y contraseña de Gitea (`secret/data/git-credentials`).
- **✅ Salida esperada**:
  ```ini
  git.username=pilot-admin
  git.password=gitea_secret_password_2026
  [INFO] agent.template.server: (runner) rendered "/etc/vault.d/templates/git-creds.properties.ctmpl" => "/run/secrets/git-credentials.properties"
  ```

---

### Comando 23 — Consultar el Composite Backend (`git` + `vault`) en `vm-config-server` (`http://localhost:18888`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s http://localhost:18888/vault-rotation-pilot/default
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Verifica que el proceso Java de **Spring Cloud Config Server** (`:8888`) ha clonado el repositorio de Gitea y devuelve en un único JSON tanto los secretos de Vault KV v2 como las propiedades del YAML de Gitea.
- **✅ Salida esperada**:
  JSON con `"propertySources"` conteniendo `vault:vault-rotation-pilot` y `http://172.29.0.50:3000/pilot-admin/pilot-config.git/vault-rotation-pilot.yml`.

---

### Comando 24 — Verificar `vault-agent` y las credenciales SQL renderizadas en `vm-app`

- **📍 Dónde se ejecuta**: Dentro de `vm-app`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-app sh -c 'cat /run/secrets/db-dynamic.properties && cat /run/secrets/db-static.properties'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba que `vault-agent` en `vm-app` ha generado y mantiene actualizados los dos ficheros de credenciales PostgreSQL en `/run/secrets/`.
- **✅ Salida esperada**:
  ```ini
  spring.datasource.dynamic.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb
  spring.datasource.dynamic.username=v-approle-postgres-...
  ...
  spring.datasource.static.username=app_static_user
  ```

---

### Comando 25 — Verificar el microservicio Spring Boot (`vm-app`) y su estado en `/api/pilot/state`

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s http://localhost:18080/api/pilot/state
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba que `java -jar /opt/app/app.jar` está arriba en el puerto `8080` (`18080` en Host), conectado tanto a PostgreSQL (`vm-db`) como a Spring Cloud Config Server (`vm-config-server`).
- **✅ Salida esperada**:
  JSON con los 6 nodos (`vault`, `db`, `app`, `ansible`, `git`, `configServer`), `credentials` y `springCloudConfig`.

---

## 🔄 Fase 7: Comandos de Prueba en Vivo (Rotación SQL Dinámica, Estática y Hot-Reload `@RefreshScope`)

Con las 6 máquinas funcionando, ejecuta estos 3 últimos comandos para disparar y verificar en directo las rotaciones y recargas en caliente.

---

### Comando 26 — Generar al vuelo un nuevo usuario SQL dinámico en Vault (`postgres-dynamic-role`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`) o contra `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -X POST http://localhost:18080/api/pilot/rotate/dynamic
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Pide a Vault un nuevo lease dinámico para PostgreSQL (`CREATE ROLE "v-approle-postgres-..."`), actualiza `/run/secrets/db-dynamic.properties` y hace que `RotatableDataSourceManager` recree `HikariPool-DYNAMIC` en caliente con un nuevo `pg_backend_pid`.
- **✅ Salida esperada**:
  ```json
  {"rotated":true,"mode":"DYNAMIC","credential":{"username":"v-approle-postgres-...","currentBackendPid":...}}
  ```

---

### Comando 27 — Forzar el cambio inmediato de la contraseña del usuario SQL estático (`app_static_user`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -X POST http://localhost:18080/api/pilot/rotate/static
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Ordena a Vault ejecutar `ALTER USER "app_static_user" WITH PASSWORD '...'` en PostgreSQL ahora mismo, actualiza `/run/secrets/db-static.properties` y recrea `HikariPool-STATIC` sin perder ninguna consulta SQL.
- **✅ Salida esperada**:
  ```json
  {"rotated":true,"mode":"STATIC","credential":{"username":"app_static_user","passwordHash":"...","currentBackendPid":...}}
  ```

---

### Comando 28 — Hacer un Commit en Gitea + Rotar Secreto KV v2 en Vault + Recargar `@RefreshScope` en Caliente

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -X POST http://localhost:18080/api/pilot/config/refresh
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Ejecuta de extremo a extremo el flujo de configuración centralizada sin reiniciar `vm-app`:
  1. Crea un nuevo commit en `vault-rotation-pilot.yml` dentro de **Gitea (`vm-git`)** vía su API HTTP.
  2. Rota el secreto `secret/data/vault-rotation-pilot` en **HashiCorp Vault (`vm-vault`)**.
  3. Invoca `ContextRefresher.refresh()` en **Spring Boot (`vm-app`)**, que consulta a **`vm-config-server` (`:8888`)** y actualiza el bean `@RefreshScope` (`DynamicConfigProperties`) en vivo.
- **✅ Salida esperada**:
  ```json
  {"refreshed":true,"commitSha":"...","springCloudConfig":{"customTag":"git-v...","vaultKvSignature":"VAULT-KV-SIG-ROTATED-..."}}
  ```

---

## 🔗 ¿Dónde seguir?

- 📘 **[Volver a la Guía Explicada para Dummies (`docs/HOWTO-DUMMIES.md`)](HOWTO-DUMMIES.md)**: Con la analogía del hotel de alta seguridad, los 4 diagramas Mermaid y la guía visual de la consola web de 6 nodos.
- 🏠 **[Volver al `README.md` principal](../README.md)**: Resumen de arquitectura, tabla de red de las 6 VMs y estructura del proyecto.

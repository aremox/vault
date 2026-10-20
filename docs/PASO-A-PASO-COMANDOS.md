# 🛠️ Manual de Comandos 1 por 1 para Dummies: De Cero a Todo Montado

> **¿Para quién es esta guía?**
> Si nunca has montado HashiCorp Vault, Ansible, PostgreSQL y Spring Boot juntos y quieres **ir ejecutando los comandos 1 por 1 sin dar absolutamente nada por supuesto**, estás en el sitio correcto.
>
> Cada comando de este manual tiene una **Ficha para Dummies** con 4 datos clave:
> 1. **📍 Dónde se ejecuta**: Para que nunca dudes en qué ventana o máquina tienes que escribirlo.
> 2. **💻 Comando exacto copiable**: Listo para copiar y pegar.
> 3. **🧠 ¿Qué hace este comando? (En cristiano)**: Explicación sencilla, sin tecnicismos oscuros.
> 4. **✅ Salida esperada**: Qué debe responder la pantalla para que sepas al 100% que todo ha salido bien antes de pasar al siguiente número.

---

## 🗺️ Índice Rápido: Elige tu Aventura

Este manual incluye **dos recorridos completos**:

- **[Recorrido A — Modo Docker Paso a Paso (12 comandos desde tu PC)](#-recorrido-a--modo-docker-paso-a-paso-12-comandos-desde-tu-pc)**:
  Enciendes las 4 máquinas virtuales (`vm-db`, `vm-vault`, `vm-ansible`, `vm-app`) **una por una** desde la terminal de tu ordenador y compruebas que cada pieza funciona antes de encender la siguiente.
- **[Recorrido B — Modo Manual "Destripado" (Los 22 comandos internos 1 por 1)](#-recorrido-b--modo-manual-destripado-los-22-comandos-internos-1-por-1)**:
  Entras hasta la cocina de cada máquina virtual para ver y ejecutar **1 por 1** todos los comandos reales que construyen el sistema por dentro (crear usuarios en PostgreSQL, inicializar y abrir la cámara acorazada de Vault, crear roles dinámicos y estáticos, enviar credenciales con Ansible y arrancar el agente y la aplicación Java).

---

## 🧭 Mapa Visual de los 22 Comandos Internos (Recorrido B)

En este diagrama puedes ver en qué orden exacto se ejecutan los **22 comandos internos** y qué máquina habla con cuál en cada paso:

```mermaid
sequenceDiagram
    autonumber
    participant DB as 🗄️ vm-db (PostgreSQL)<br/>172.29.0.20:5432
    participant VAULT as 🔐 vm-vault (Vault Server)<br/>172.29.0.10:8200
    participant ANS as 🤖 vm-ansible (Ansible)<br/>172.29.0.40
    participant APP as ☕ vm-app (Vault Agent + Java)<br/>172.29.0.30:8080

    Note over DB: FASE 1: Preparar Base de Datos
    DB->>DB: [Cmd 1] Crear superusuario vault_admin
    DB->>DB: [Cmd 2] Crear grupo pilot_app_group y app_static_user
    DB->>DB: [Cmd 3] Crear tabla connection_audit_log y dar permisos

    Note over VAULT: FASE 2: Encender y Abrir la Caja Fuerte
    VAULT->>VAULT: [Cmd 4] Arrancar vault server (config.hcl)
    VAULT->>VAULT: [Cmd 5] Inicializar (vault operator init -> Unseal Key + Root Token)
    VAULT->>VAULT: [Cmd 6] Abrir puerta acorazada (vault operator unseal)
    VAULT->>VAULT: [Cmd 7] Login de administrador (export VAULT_TOKEN)

    Note over VAULT,DB: FASE 3: Conectar Vault con Postgres y Crear Roles
    VAULT->>VAULT: [Cmd 8] Activar motor database/
    VAULT->>DB: [Cmd 9] Conectar Vault a Postgres usando vault_admin
    VAULT->>VAULT: [Cmd 10] Crear Rol Dinámico (TTL 60s, usuarios efímeros)
    VAULT->>VAULT: [Cmd 11] Crear Rol Estático (rotación auto cada 60s)
    VAULT->>VAULT: [Cmd 12] Cargar política de seguridad app-db-policy
    VAULT->>VAULT: [Cmd 13] Activar login de máquinas (auth enable approle)
    VAULT->>VAULT: [Cmd 14] Crear AppRole spring-app-role

    Note over ANS,APP: FASE 4: Ansible Reparte el Carnet de Identidad
    ANS->>VAULT: [Cmd 15] Pedir role_id público por HTTP API
    ANS->>VAULT: [Cmd 16] Generar secret_id de un uso por HTTP API
    ANS->>APP: [Cmd 17] Copiar role_id y secret_id por SSH (/etc/vault.d, chmod 0600)

    Note over APP,DB: FASE 5: Vault Agent y App Java en Acción
    APP->>VAULT: [Cmd 18] Arrancar vault agent -> Auto-Auth y pedir claves a Vault
    APP->>DB: [Cmd 19] Arrancar java -jar app.jar -> Conectar a Postgres sin claves en código

    Note over VAULT,DB: FASE 6: Comandos de Prueba y Rotación en Vivo
    VAULT->>DB: [Cmd 20] Generar usuario dinámico nuevo al vuelo
    VAULT->>DB: [Cmd 21] Forzar cambio de password del usuario estático
    DB->>DB: [Cmd 22] Consultar tabla de auditoría connection_audit_log
```

---

# 🚀 Recorrido A — Modo Docker Paso a Paso (12 Comandos desde tu PC)

En este recorrido vamos a levantar el laboratorio **pieza por pieza** desde la carpeta del proyecto (`D:\Programacion\IA\vault`). Así verás cómo nace cada máquina en orden lógico en lugar de lanzarlo todo a ciegas.

> [!TIP]
> **¿Qué terminal uso en Windows?**
> Puedes abrir **Git Bash** o **PowerShell** en la carpeta `D:\Programacion\IA\vault`. Todos los comandos de abajo incluyen `MSYS_NO_PATHCONV=1` cuando se usa `docker exec` para que funcionen directamente en Git Bash sin que Windows cambie las barras `/` de las rutas. Si usas PowerShell y algún comando empieza por `MSYS_NO_PATHCONV=1`, puedes ejecutarlo con `bash -c "..."` o quitar ese prefijo.

---

### Paso A.1 — Comprobar que Docker está despierto

- **📍 Dónde se ejecuta**: En tu PC (`Host: Git Bash / PowerShell`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose version && docker info --format '{{.ServerVersion}}'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le pregunta a tu ordenador dos cosas: si tiene la herramienta `docker compose` instalada y si el motor de Docker Desktop está encendido y respondiendo. Si Docker Desktop estuviera cerrado, aquí te avisaría antes de empezar.
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
  Apaga cualquier contenedor del piloto que hubiera quedado encendido de una prueba anterior y borra los discos temporales (`-v` = volúmenes). Es como "formatear la mesa de trabajo" para asegurarnos de que empezamos 100% limpios.
- **✅ Salida esperada**:
  ```text
  [+] Running 7/7
   ✔ Container vm-ansible  Removed
   ✔ Container vm-app      Removed
   ✔ Container vm-vault    Removed
   ✔ Container vm-db       Removed
   ✔ Volume vault_db-data  Removed
   ✔ Network vault-pilot-net Removed
  ```
  *(Si era la primera vez que lo ejecutabas, simplemente no mostrará contenedores que borrar y terminará sin error).*

---

### Paso A.3 — Construir las imágenes de las máquinas virtuales

- **📍 Dónde se ejecuta**: En tu PC (`Host`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose build
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Lee los planos de construcción (`Dockerfile`) de `vm-ansible` (que instala Ansible y cliente SSH) y de `vm-app` (que compila el código Java 21 con Maven, instala OpenSSH Server y descarga el binario de `vault agent`). Todavía no enciende ninguna máquina: solo deja sus "plantillas" listas.
- **✅ Salida esperada**:
  ```text
  [+] Building ... FINISHED
   ✔ vm-ansible  Built
   ✔ vm-app      Built
  ```

---

### Paso A.4 — Encender SOLO la Máquina 1: Base de Datos PostgreSQL (`vm-db`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`), dentro de `D:\Programacion\IA\vault`.
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d vm-db
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea la red privada `vault-pilot-net` (`172.29.0.0/24`) y enciende en segundo plano (`-d`) únicamente la primera máquina: el servidor de base de datos PostgreSQL 16 (`vm-db`, IP `172.29.0.20`). Al arrancar por primera vez, PostgreSQL ejecuta automáticamente el script `infra/db/init.sql`.
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
  Se mete dentro de la máquina `vm-db` y le pide a PostgreSQL dos listas:
  1. `\du`: la lista de usuarios/roles creados (`vault_admin`, `pilot_app_group`, `app_static_user`).
  2. `\dt`: la lista de tablas en la base de datos `pilotdb` (`connection_audit_log`).
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

### Paso A.6 — Encender la Máquina 2: Servidor HashiCorp Vault (`vm-vault`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d vm-vault
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende la segunda máquina virtual (`vm-vault`, IP `172.29.0.10`). Al arrancar, ejecuta su guion `infra/vault/scripts/bootstrap-vault.sh` que inicializa la caja fuerte, la abre (unseal), se conecta a `vm-db` y configura el Rol Dinámico, el Rol Estático y el AppRole para la aplicación.
- **✅ Salida esperada**:
  ```text
  [+] Running 1/1
   ✔ Container vm-vault  Started
  ```

---

### Paso A.7 — Comprobar que Vault está abierto (`Sealed: false`) y configurado

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault vault status
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Consulta el estado de la cámara acorazada de Vault. Lo más importante es fijarse en dos líneas: `Initialized: true` (ya tiene llaves maestras) y `Sealed: false` (la puerta acorazada está abierta y lista para entregar secretos).
- **✅ Salida esperada**:
  ```text
  Key             Value
  ---             -----
  Seal Type       shamir
  Initialized     true
  Sealed          false
  Total Shares    1
  Threshold       1
  Version         1.17.x
  Storage Type    file
  ```

---

### Paso A.8 — Encender la Máquina 4 (`vm-app`) en espera de credenciales

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up -d --no-deps vm-app
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende la máquina de la aplicación (`vm-app`, IP `172.29.0.30`) sin lanzar todavía Ansible (`--no-deps`). Al arrancar, `vm-app` enciende su servidor SSH y se queda esperando pacientemente porque todavía **no tiene carnet de identidad** (`/etc/vault.d/role_id` ni `secret_id`).
- **✅ Salida esperada**:
  ```text
  [+] Running 1/1
   ✔ Container vm-app  Started
  ```
  Si miras sus logs con `docker logs vm-app`, verás:
  ```text
  [vm-app] Iniciando demonio OpenSSH Server (simulacion VM)...
  [vm-app] Esperando aprovisionamiento de /etc/vault.d/role_id y /etc/vault.d/secret_id via Ansible...
  ```

---

### Paso A.9 — Ejecutar la Máquina 3 (`vm-ansible`) para entregar las credenciales por SSH

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  docker compose up vm-ansible
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Enciende el nodo automatizador Ansible (`vm-ansible`, IP `172.29.0.40`) en primer plano para que veas todo lo que hace en directo:
  1. Habla con `vm-vault` y le pide el `role_id` y un `secret_id` nuevo.
  2. Se conecta por SSH a `vm-app` (`172.29.0.30:22`).
  3. Deposita ambos archivos en `/etc/vault.d/` con permisos blindados `0600`.
  4. Arranca el `vault agent` dentro de `vm-app` y espera hasta confirmar que se han creado los ficheros de contraseñas en `/run/secrets/`.
- **✅ Salida esperada**:
  ```text
  PLAY RECAP *********************************************************************
  vm-app                     : ok=12   changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
  vm-ansible exited with code 0
  ```

---

### Paso A.10 — Comprobar las contraseñas generadas por Vault Agent en la memoria RAM de `vm-app`

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-app sh -c 'cat /run/secrets/db-dynamic.properties && echo "---" && cat /run/secrets/db-static.properties'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Muestra en pantalla los dos ficheros que `vault agent` acaba de escribir dentro de la carpeta en memoria RAM (`/run/secrets/`) de `vm-app`. Verás cómo el usuario dinámico tiene un nombre autogenerado tipo `v-approle-postgres-dynamic-...` y una contraseña aleatoria de 20 caracteres.
- **✅ Salida esperada**:
  ```ini
  # Renderizado automaticamente por Vault Agent (Rol Dinamico)
  db.dynamic.url=jdbc:postgresql://172.29.0.20:5432/pilotdb
  db.dynamic.username=v-approle-postgres-dynamic-xxxx-1776xxxxxx
  db.dynamic.password=A9x...
  ---
  # Renderizado automaticamente por Vault Agent (Rol Estatico)
  db.static.url=jdbc:postgresql://172.29.0.20:5432/pilotdb
  db.static.username=app_static_user
  db.static.password=K7m...
  ```

---

### Paso A.11 — Comprobar que la App Java Spring Boot responde y abrir la Web Animada

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s http://localhost:18080/api/pilot/state
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Llama al endpoint web de nuestra aplicación Java 21 Spring Boot (que ya ha arrancado automáticamente en cuanto vio aparecer los ficheros del Paso A.10). Devuelve un JSON con el estado en vivo de las 4 máquinas, los usuarios actuales y las últimas filas grabadas en PostgreSQL.
- **✅ Salida esperada**:
  Un texto JSON que empieza por:
  ```json
  {"timestamp":"...","vaultHealth":{"reachable":true,"initialized":true,"sealed":false},"dynamicRole":{"mode":"DYNAMIC","dbUsername":"v-approle-postgres-dynamic-...","status":"UP" ...}}
  ```
  🎉 **¡En este momento ya puedes abrir en tu navegador [`http://localhost:18080`](http://localhost:18080) y ver el panel animado funcionando!**

---

### Paso A.12 — Pasar los dos exámenes automáticos del laboratorio (`verify-pilot.sh` y `verify-ui.sh`)

- **📍 Dónde se ejecuta**: En tu PC (`Host` con Git Bash).
- **💻 Comando exacto copiable**:
  ```bash
  bash scripts/verify-pilot.sh && bash scripts/verify-ui.sh
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Ejecuta nuestras dos suites de pruebas automatizadas:
  1. `verify-pilot.sh`: comprueba contenedores, Vault, Ansible, espera a que la clave dinámica rote sola al caducar los 60 segundos, fuerza la rotación de la clave estática y verifica la tabla de auditoría en PostgreSQL.
  2. `verify-ui.sh`: comprueba la página web y dispara los botones de rotación por API REST.
- **✅ Salida esperada**:
  ```text
  ====================================================================
   RESULTADO FINAL: PILOTO VERIFICADO CON EXITO (EXIT 0)
  ====================================================================
  ...
  === [VERIFY-UI] TODOS LOS TESTS DE CONSOLA WEB Y API PASARON (EXIT 0) ===
  ```

---

# 🔬 Recorrido B — Modo Manual "Destripado" (Los 22 Comandos Internos 1 por 1)

¿Quieres saber **exactamente qué comandos se ejecutan por dentro** de cada una de las 4 máquinas virtuales sin que ningún script lo haga por ti, o quieres ir lanzándolos tú mismo uno detrás de otro para aprender cómo funciona cada herramienta?

Aquí tienes la lista íntegra de los **22 comandos reales**, en orden cronológico estricto.

> [!NOTE]
> **¿Cómo uso este Recorrido B?**
> Si ya tienes el entorno levantado del Recorrido A, puedes ejecutar cualquiera de estos comandos ahora mismo (son idempotentes, es decir, se pueden volver a lanzar para practicar y ver su respuesta real).

---

## 🗄️ Fase 1: Preparar la Base de Datos en `vm-db` (PostgreSQL 16)

Antes de que Vault pueda gestionar permisos o rotar contraseñas en una base de datos, PostgreSQL necesita tener creados:
1. Un usuario "jefe de llaves" para Vault (`vault_admin`).
2. Un grupo de permisos para la aplicación (`pilot_app_group`) y un usuario fijo (`app_static_user`).
3. Una tabla donde nuestra aplicación Java pueda escribir para demostrar que entra sin problemas (`connection_audit_log`).

---

### Comando 1 — Crear el superusuario `vault_admin` para que Vault mande en PostgreSQL

- **📍 Dónde se ejecuta**: Dentro de `vm-db` (lanzado desde tu PC con `docker exec`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'vault_admin') THEN CREATE ROLE vault_admin WITH LOGIN SUPERUSER CREATEROLE PASSWORD 'vault_admin_pwd'; END IF; END \$\$;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Se conecta como administrador de PostgreSQL y crea el usuario `vault_admin` con el permiso especial `CREATEROLE`. Esta cuenta **no la usará nunca la aplicación Java**: solo la conocerá HashiCorp Vault para poder crear nuevos usuarios efímeros cada 60 segundos y cambiar contraseñas.
- **✅ Salida esperada**:
  ```text
  DO
  ```

---

### Comando 2 — Crear el grupo de permisos `pilot_app_group` y el usuario fijo `app_static_user`

- **📍 Dónde se ejecuta**: Dentro de `vm-db` (lanzado desde tu PC con `docker exec`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'pilot_app_group') THEN CREATE ROLE pilot_app_group NOLOGIN; END IF; IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_static_user') THEN CREATE ROLE app_static_user WITH LOGIN PASSWORD 'initial_static_pwd' IN ROLE pilot_app_group; END IF; END \$\$;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea dos cosas en PostgreSQL:
  1. `pilot_app_group`: un "grupo" sin login al que daremos permisos sobre las tablas. Todos los usuarios temporales que cree Vault heredarán los permisos de este grupo.
  2. `app_static_user`: el usuario de toda la vida para el **Rol Estático**. Nace con una contraseña inicial (`initial_static_pwd`) que Vault cambiará enseguida por una aleatoria que ni tú ni nadie conocerá.
- **✅ Salida esperada**:
  ```text
  DO
  ```

---

### Comando 3 — Crear la tabla `connection_audit_log` y dar permisos al grupo de la App

- **📍 Dónde se ejecuta**: Dentro de `vm-db` (lanzado desde tu PC con `docker exec`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "CREATE TABLE IF NOT EXISTS public.connection_audit_log (id BIGSERIAL PRIMARY KEY, credential_mode VARCHAR(16) NOT NULL, db_username VARCHAR(128) NOT NULL, backend_pid INTEGER NOT NULL, executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()); GRANT CONNECT ON DATABASE pilotdb TO pilot_app_group; GRANT USAGE ON SCHEMA public TO pilot_app_group; GRANT SELECT, INSERT ON public.connection_audit_log TO pilot_app_group; GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pilot_app_group;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea la tabla de auditoría donde la aplicación Java insertará un registro cada pocos segundos indicando con qué usuario se ha conectado (`db_username`) y si era dinámico o estático (`credential_mode`). Además, otorga permiso de lectura e inserción (`SELECT, INSERT`) al grupo `pilot_app_group`.
- **✅ Salida esperada**:
  ```text
  CREATE TABLE
  GRANT
  GRANT
  GRANT
  GRANT
  ```

---

## 🔐 Fase 2: Encender, Inicializar y Abrir la Cámara Acorazada en `vm-vault`

Cuando instalas HashiCorp Vault desde cero, arranca **sin inicializar** (no tiene llaves maestras) y **sellado (`Sealed: true`)** (nadie puede leer ni escribir nada dentro). Estos 4 comandos son el ritual de apertura de Vault.

---

### Comando 4 — Arrancar el proceso del servidor Vault (`vault server`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault` (proceso principal del contenedor).
- **💻 Comando exacto copiable** *(para comprobar que está corriendo y ver su configuración)*:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c "ps aux | grep 'vault server' && cat /vault/config/config.hcl"
  ```
  *(Nota: el comando real que lanza el servidor al encender la máquina es `vault server -config=/vault/config/config.hcl &`).*
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  El binario `vault server -config=/vault/config/config.hcl` pone en marcha el motor de Vault escuchando en el puerto `8200` y guardando los datos cifrados en disco (`/vault/file`).
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

### Comando 5 — Inicializar Vault por primera vez (`vault operator init`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'if [ ! -f /vault/bootstrap/init.json ]; then vault operator init -key-shares=1 -key-threshold=1 -format=json > /vault/bootstrap/init.json; fi && cat /vault/bootstrap/init.json'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  `vault operator init -key-shares=1 -key-threshold=1` se ejecuta **una sola vez en la vida de Vault**. Genera la clave criptográfica maestra que cifra todo el disco de Vault y devuelve dos joyas en formato JSON:
  - `unseal_keys_b64`: la llave física para abrir la puerta acorazada cada vez que el servidor se reinicie.
  - `root_token`: el pase de superadministrador inicial de Vault.
- **✅ Salida esperada**:
  ```json
  {
    "unseal_keys_b64": [
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ],
    "root_token": "hvs.xxxxxxxxxxxxxxxxxxxxxxxx"
  }
  ```

---

### Comando 6 — Desellar la puerta acorazada (`vault operator unseal`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'vault operator unseal $(cat /vault/bootstrap/unseal.key)'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Introduce la llave de desellado (`Unseal Key`) en la cerradura de Vault. A partir de este instante, Vault carga su llave maestra en memoria RAM y cambia su estado de `Sealed: true` (bloqueado) a `Sealed: false` (abierto y operativo).
- **✅ Salida esperada**:
  ```text
  Key             Value
  ---             -----
  Seal Type       shamir
  Initialized     true
  Sealed          false
  ```

---

### Comando 7 — Autenticarse como Administrador (`vault login` / `VAULT_TOKEN`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault token lookup'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Exporta la variable `VAULT_TOKEN` con el `Root Token` obtenido en el Comando 5 y ejecuta `vault token lookup` para verificar que Vault nos reconoce como el superusuario `root`. Sin esto, Vault no nos dejaría crear motores ni políticas en los siguientes pasos.
- **✅ Salida esperada**:
  ```text
  Key                 Value
  ---                 -----
  display_name        root
  id                  hvs.xxxxxxxxxxxx
  policies            [root]
  ```

---

## ⚙️ Fase 3: Configurar Motores de Base de Datos, Roles y AppRole en `vm-vault`

Con la cámara acorazada abierta, ahora le enseñamos a Vault cómo hablar con PostgreSQL y qué reglas de rotación de contraseñas debe aplicar.

---

### Comando 8 — Activar el motor de secretos de Bases de Datos (`vault secrets enable database`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && (vault secrets list | grep -q "^database/" || vault secrets enable database) && vault secrets list'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Por defecto, Vault viene vacío como un móvil recién comprado sin apps. El comando `vault secrets enable database` instala y activa el "módulo de bases de datos" en la ruta `database/`, que sabe hablar con PostgreSQL, MySQL, Oracle, etc.
- **✅ Salida esperada**:
  ```text
  Path          Type         Accessor              Description
  ----          ----         --------              -----------
  cubbyhole/    cubbyhole    cubbyhole_xxxx        per-token private secret storage
  database/     database     database_xxxx         n/a
  sys/          system       system_xxxx           system endpoints used for control...
  ```

---

### Comando 9 — Conectar Vault con PostgreSQL (`database/config/postgres-pilot`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write database/config/postgres-pilot plugin_name=postgresql-database-plugin allowed_roles="postgres-dynamic-role,postgres-static-role" connection_url="postgresql://{{username}}:{{password}}@172.29.0.20:5432/pilotdb?sslmode=disable" username="vault_admin" password="vault_admin_pwd"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le entrega a Vault la dirección IP de PostgreSQL (`172.29.0.20:5432/pilotdb`) y las credenciales del usuario administrador `vault_admin` que creamos en el **Comando 1**. Además, le dice qué dos roles tienen permiso para usar esta conexión (`postgres-dynamic-role` y `postgres-static-role`). En ese mismo instante, Vault prueba la conexión con PostgreSQL para verificar que funciona.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: database/config/postgres-pilot
  ```

---

### Comando 10 — Crear el Rol Dinámico con caducidad de 60 segundos (`postgres-dynamic-role`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write database/roles/postgres-dynamic-role db_name=postgres-pilot creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '\''{{password}}'\'' VALID UNTIL '\''{{expiration}}'\'' IN ROLE pilot_app_group;" revocation_statements="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '\''{{name}}'\''; DROP ROLE IF EXISTS \"{{name}}\";" default_ttl="60s" max_ttl="120s"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Define la receta para fabricar **usuarios de usar y tirar**:
  - `creation_statements`: el comando SQL que Vault lanzará cada vez que alguien le pida entrar (`CREATE ROLE ... IN ROLE pilot_app_group`).
  - `revocation_statements`: el comando SQL que Vault lanzará cuando pasen los 60 segundos para echar al usuario y borrarlo de PostgreSQL (`DROP ROLE`).
  - `default_ttl="60s"`: cada usuario dinámico vive **60 segundos** (y como máximo 120 segundos).
- **✅ Salida esperada**:
  ```text
  Success! Data written to: database/roles/postgres-dynamic-role
  ```

---

### Comando 11 — Crear el Rol Estático con rotación cada 60 segundos (`postgres-static-role`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write database/static-roles/postgres-static-role db_name=postgres-pilot username="app_static_user" rotation_statements="ALTER USER \"{{name}}\" WITH PASSWORD '\''{{password}}'\'';" rotation_period="60s"'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le dice a Vault que tome el control del usuario fijo `app_static_user` (creado en el **Comando 2**) y que ejecute automáticamente un `ALTER USER ... WITH PASSWORD` **cada 60 segundos** (`rotation_period="60s"`). Nada más ejecutar este comando, Vault ya le cambia la contraseña inicial por una secreta.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: database/static-roles/postgres-static-role
  ```

---

### Comando 12 — Cargar la Política de Seguridad de Mínimo Privilegio (`app-db-policy`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault policy write app-db-policy /vault/policies/app-db-policy.hcl && vault policy read app-db-policy'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Registra en Vault las normas del contrato `app-db-policy.hcl`. Esta política dice que nuestra aplicación Java **solo tiene permiso de lectura (`read`)** sobre dos rutas:
  1. `database/creds/postgres-dynamic-role` (para pedir su usuario dinámico).
  2. `database/static-creds/postgres-static-role` (para leer la contraseña actual del usuario estático).
  Si la aplicación intentara borrar algo o leer secretos de otro proyecto, Vault le daría un portazo (`403 Permission Denied`).
- **✅ Salida esperada**:
  ```hcl
  Success! Uploaded policy: app-db-policy
  path "database/creds/postgres-dynamic-role" {
    capabilities = ["read"]
  }
  path "database/static-creds/postgres-static-role" {
    capabilities = ["read"]
  }
  ```

---

### Comando 13 — Activar el método de login para máquinas (`vault auth enable approle`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && (vault auth list | grep -q "^approle/" || vault auth enable approle) && vault auth list'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Las personas entran en un sistema con usuario y contraseña o huella dactilar, pero ¿cómo entra un servidor o un microservicio sin que haya un humano tecleando? Con **AppRole**, el sistema de identificación para máquinas de Vault. Este comando lo activa en la ruta `approle/`.
- **✅ Salida esperada**:
  ```text
  Path        Type       Accessor               Description
  ----        ----       --------               -----------
  approle/    approle    auth_approle_xxxx      n/a
  token/      token      auth_token_xxxx        token based credentials
  ```

---

### Comando 14 — Crear el perfil AppRole de la aplicación (`spring-app-role`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write auth/approle/role/spring-app-role token_policies="app-db-policy" token_ttl="10m" token_max_ttl="30m" secret_id_ttl="10m" secret_id_num_uses=0'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Crea el carnet de identidad `spring-app-role` para nuestra máquina `vm-app` y lo ata a la política `app-db-policy` que subimos en el **Comando 12**. Así, quien se identifique con este AppRole recibirá un token válido durante 10 minutos (`token_ttl="10m"`) con permiso exclusivo para leer las claves de base de datos.
- **✅ Salida esperada**:
  ```text
  Success! Data written to: auth/approle/role/spring-app-role
  ```

---

## 🤖 Fase 4: Negociar y Entregar el Carnet de Identidad con Ansible (`vm-ansible` -> `vm-app`)

Para que `vm-app` pueda autenticarse en Vault mediante AppRole, necesita dos piezas:
1. **`role_id`**: el identificador fijo del rol (como el DNI o nombre de usuario de la máquina).
2. **`secret_id`**: un pase secreto generado al vuelo por Vault.

En vez de copiarlos a mano, **`vm-ansible`** se los pide a Vault por HTTP API y los inyecta por SSH dentro de `vm-app`.

---

### Comando 15 — Pedir a Vault el identificador `role_id` del AppRole

- **📍 Dónde se ejecuta**: Desde `vm-vault` / `vm-ansible` contra la API de Vault (`http://172.29.0.10:8200`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault read -field=role_id auth/approle/role/spring-app-role/role-id && echo ""'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Consulta a Vault cuál es el número de serie público (`role_id`) asignado al perfil `spring-app-role`. Es la primera mitad de la llave que necesita `vm-app`.
- **✅ Salida esperada**:
  Un identificador UUID como:
  ```text
  9f4d8b1a-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  ```

---

### Comando 16 — Generar un pase secreto nuevo `secret_id` en Vault

- **📍 Dónde se ejecuta**: Contra la API de Vault (`vm-vault`).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault write -f -field=secret_id auth/approle/role/spring-app-role/secret-id && echo ""'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le pide a Vault que fabrique un `secret_id` nuevo de paquete para `spring-app-role`. Es la segunda mitad de la llave. Cuando `vault agent` la use en `vm-app`, borrará el archivo del disco automáticamente (`remove_secret_id_file_after_reading = true`) para que ningún intruso pueda robarlo.
- **✅ Salida esperada**:
  Un UUID secreto recién generado:
  ```text
  3c7e1a2b-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  ```

---

### Comando 17 — Ejecutar el Playbook de Ansible que inyecta `role_id` y `secret_id` por SSH en `vm-app`

- **📍 Dónde se ejecuta**: Dentro de `vm-ansible` (lanzado desde tu PC).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-ansible ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Automatiza los Comandos 15 y 16, se conecta por SSH (`puerto 22`) a la máquina `vm-app` (`172.29.0.30`), guarda `/etc/vault.d/role_id` y `/etc/vault.d/secret_id` con permisos `0600` (solo legibles por `root`) y despierta al demonio `vault agent`.
- **✅ Salida esperada**:
  ```text
  PLAY [Negociar role_id + secret_id en Vault y desplegarlos por SSH en vm-app] **
  ...
  PLAY RECAP *********************************************************************
  vm-app                     : ok=12   changed=3    unreachable=0    failed=0
  ```

---

## ☕ Fase 5: Vault Agent y Aplicación Java 21 Spring Boot en `vm-app`

Ya tenemos a `vm-app` con su `role_id` y `secret_id`. Veamos los dos procesos que corren dentro de `vm-app` y cómo comprobarlos.

---

### Comando 18 — Arrancar y verificar el demonio `vault agent` en `vm-app`

- **📍 Dónde se ejecuta**: Dentro de `vm-app`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-app sh -c 'ps aux | grep "vault agent" && tail -n 10 /var/log/vault-agent/agent.log'
  ```
  *(Nota: el comando que lo arranca en segundo plano es `vault agent -config=/etc/vault.d/vault-agent.hcl >/var/log/vault-agent/agent.log 2>&1 &`).*
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  `vault agent` es el "secretario automático" que vive dentro de `vm-app`:
  1. Lee `/etc/vault.d/role_id` y `/etc/vault.d/secret_id`, hace login en Vault y **borra** el archivo `secret_id` por seguridad.
  2. Guarda el token obtenido en `/run/secrets/vault-token`.
  3. Rellena las dos plantillas (`/etc/vault.d/templates/*.ctmpl`) y escribe las contraseñas reales en `/run/secrets/db-dynamic.properties` y `/run/secrets/db-static.properties`.
  4. Cada ~60 segundos, cuando la contraseña caduca o rota, **actualiza esos dos ficheros solo**, sin que nadie tenga que tocar nada.
- **✅ Salida esperada**:
  ```text
  [INFO]  agent.auth.handler: authentication successful, sending token to sink
  [INFO]  agent.template.server: (runner) rendered "/etc/vault.d/templates/db-dynamic.properties.ctmpl" => "/run/secrets/db-dynamic.properties"
  [INFO]  agent.template.server: (runner) rendered "/etc/vault.d/templates/db-static.properties.ctmpl" => "/run/secrets/db-static.properties"
  ```

---

### Comando 19 — Arrancar y verificar el microservicio Java 21 Spring Boot (`java -jar /opt/app/app.jar`)

- **📍 Dónde se ejecuta**: Dentro de `vm-app`.
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-app sh -c 'ps aux | grep "java -jar /opt/app/app.jar"'
  ```
  *(Nota: el comando que arranca la aplicación en `vm-app` es `java -jar /opt/app/app.jar`).*
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Pone en marcha la aplicación Spring Boot en el puerto `8080` (expuesto en tu PC como `18080`). Su componente `RotatableDataSourceManager` vigila cada pocos segundos los ficheros `/run/secrets/db-dynamic.properties` y `/run/secrets/db-static.properties`. Cada vez que `vault agent` cambia una contraseña, Java actualiza su pool de conexiones HikariCP en caliente **sin reiniciar la aplicación y sin cortar el servicio**.
- **✅ Salida esperada**:
  ```text
  root   ...  java -jar /opt/app/app.jar
  ```

---

## 🔄 Fase 6: Comandos de Prueba y Rotación Manual 1 por 1

Con todo montado, ejecuta estos 3 últimos comandos para ver con tus propios ojos cómo Vault fabrica usuarios nuevos, cómo fuerza el cambio de contraseña y cómo queda todo registrado en PostgreSQL.

---

### Comando 20 — Pedir a mano una credencial dinámica nueva a Vault (expira a los 60s)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault` (lanzado desde tu PC).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault read database/creds/postgres-dynamic-role'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Le pide a Vault una cuenta dinámica nueva para PostgreSQL ahora mismo. Si ejecutas este mismo comando 3 veces seguidas, verás que **cada vez te da un `username` y un `password` completamente distintos**, y todos ellos desaparecerán solos de PostgreSQL 60 segundos después (`lease_duration: 1m`).
- **✅ Salida esperada**:
  ```text
  Key                Value
  ---                -----
  lease_id           database/creds/postgres-dynamic-role/xxxx
  lease_duration     1m
  lease_renewable    true
  password           vX9-xxxxxxxxxxxx
  username           v-root-postgres-dynamic-ro-xxxx-1776xxxxxx
  ```

---

### Comando 21 — Forzar a mano el cambio inmediato de la contraseña del Rol Estático

- **📍 Dónde se ejecuta**: Dentro de `vm-vault` (lanzado desde tu PC).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && echo "=== ANTES ===" && vault read database/static-creds/postgres-static-role && vault write -f database/rotate-role/postgres-static-role && echo "=== DESPUES ===" && vault read database/static-creds/postgres-static-role'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Muestra la contraseña actual de `app_static_user` (`=== ANTES ===`), lanza la orden `vault write -f database/rotate-role/postgres-static-role` para obligar a Vault a cambiarla en PostgreSQL en este mismo segundo sin esperar a que se cumpla el minuto, y vuelve a mostrarla (`=== DESPUES ===`). Verás que el `username` sigue siendo `app_static_user`, pero el `password` ha cambiado al instante y el contador `ttl` vuelve a `1m`.
- **✅ Salida esperada**:
  ```text
  === ANTES ===
  password             OldPass123...
  ttl                  24s
  username             app_static_user
  Success! Data written to: database/rotate-role/postgres-static-role
  === DESPUES ===
  password             NewPass987...
  ttl                  1m
  username             app_static_user
  ```

---

### Comando 22 — Consultar la tabla de auditoría en PostgreSQL para ver el historial real de usuarios

- **📍 Dónde se ejecuta**: Dentro de `vm-db` (lanzado desde tu PC).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-db psql -U postgres -d pilotdb -c "SELECT id, credential_mode, db_username, backend_pid, executed_at FROM public.connection_audit_log ORDER BY id DESC LIMIT 10;"
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Consulta las últimas 10 conexiones que la aplicación Java ha realizado contra PostgreSQL. Aquí tienes la prueba reina del piloto:
  - En las filas `STATIC` el usuario siempre es `app_static_user` (aunque su contraseña haya cambiado decenas de veces).
  - En las filas `DYNAMIC` el nombre del usuario `v-approle-postgres-dynamic-...` va cambiando cada minuto a medida que nacen usuarios nuevos y mueren los antiguos.
- **✅ Salida esperada**:
  ```text
    id  | credential_mode |                    db_username                    | backend_pid |          executed_at          
  ------+-----------------+---------------------------------------------------+-------------+-------------------------------
    142 | STATIC          | app_static_user                                   |         914 | 2026-10-19 19:25:10.112+00
    141 | DYNAMIC         | v-approle-postgres-dynamic-xxxx-1776626685        |         913 | 2026-10-19 19:25:10.105+00
    ...
  ```

---

## 🌐 Fase 7 (Spec 05): Servidor Git Gitea (`vm-git`) + Spring Cloud Config Server (`vm-config-server`) + Vault KV v2

Con la incorporación de las máquinas 5 y 6 (`vm-git` en `172.29.0.50` y `vm-config-server` en `172.29.0.60`), aquí tienes los comandos paso a paso para inspeccionar y probar la configuración centralizada y su recarga en caliente (`@RefreshScope`):

### Comando 23 — Habilitar y poblar los secretos KV v2 en `vm-vault` (`secret/git-credentials` y `secret/vault-rotation-pilot`)

- **📍 Dónde se ejecuta**: Dentro de `vm-vault` (lanzado desde tu PC).
- **💻 Comando exacto copiable**:
  ```bash
  MSYS_NO_PATHCONV=1 docker exec vm-vault sh -c 'export VAULT_TOKEN=$(cat /vault/bootstrap/root.token) && vault kv get secret/git-credentials && vault kv get secret/vault-rotation-pilot'
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Comprueba los dos secretos guardados en el motor **KV v2 (`secret/`)** de Vault:
  1. `secret/git-credentials`: guarda el usuario y contraseña de Gitea (`pilot-admin`) para que `vm-config-server` los descargue con su `vault-agent` sin tener claves hardcodeadas.
  2. `secret/vault-rotation-pilot`: guarda propiedades secretas (`pilot.vault.kv.secret-signature`) que Spring Cloud Config fusiona con el fichero YAML de Gitea.
- **✅ Salida esperada**:
  ```text
  ====== Data ======
  Key             Value
  ---             -----
  git_password    gitea_secret_password_2026
  git_username    pilot-admin
  ...
  pilot.vault.kv.secret-signature    VAULT-KV-SIG-INITIAL-9001
  ```

---

### Comando 24 — Verificar el repositorio Git y el fichero `vault-rotation-pilot.yml` en Gitea (`vm-git`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -u pilot-admin:gitea_secret_password_2026 http://localhost:13000/api/v1/repos/pilot-admin/pilot-config/contents/vault-rotation-pilot.yml
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Consulta la API HTTP del servidor Gitea (`vm-git`, puerto `13000`) para verificar que el repositorio `pilot-admin/pilot-config` y el fichero `vault-rotation-pilot.yml` están creados y accesibles. También puedes abrir `http://localhost:13000` en tu navegador.
- **✅ Salida esperada**:
  Un JSON con `"name":"vault-rotation-pilot.yml"` y el `"sha"` del commit actual en la rama `main`.

---

### Comando 25 — Consultar el Composite Backend (`git` + `vault`) en `vm-config-server` (`:18888`)

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s http://localhost:18888/vault-rotation-pilot/default
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Pregunta directamente a **Spring Cloud Config Server** (`vm-config-server`, puerto `18888`) qué configuración tiene disponible para la aplicación `vault-rotation-pilot`. Verás que devuelve dos `propertySources` combinados: uno traído de **Vault KV v2** (`vault:vault-rotation-pilot`) y otro traído del **repositorio Git de Gitea** (`http://172.29.0.50:3000/pilot-admin/pilot-config.git`).
- **✅ Salida esperada**:
  JSON con `"propertySources"` incluyendo tanto `pilot.vault.kv.secret-signature` como `pilot.config.banner` y `pilot.config.custom-tag`.

---

### Comando 26 — Hacer un Commit en Gitea + Rotar Secreto KV en Vault + Recargar `@RefreshScope` en Caliente

- **📍 Dónde se ejecuta**: En tu PC (`Host`).
- **💻 Comando exacto copiable**:
  ```bash
  curl -s -X POST http://localhost:18080/api/pilot/config/refresh
  ```
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**:
  Dispara en un solo paso toda la cadena de recarga en caliente sin reiniciar `vm-app`:
  1. Crea un nuevo commit en el fichero `vault-rotation-pilot.yml` de Gitea cambiando `pilot.config.custom-tag` y `pilot.config.banner`.
  2. Rota el secreto `secret/data/vault-rotation-pilot` en HashiCorp Vault.
  3. Ejecuta `ContextRefresher.refresh()` en Spring Boot (`vm-app`), recargando el bean `@RefreshScope` al vuelo sin interrumpir las conexiones activas a PostgreSQL.
- **✅ Salida esperada**:
  ```json
  {"refreshed":true,"commitSha":"...","springCloudConfig":{"customTag":"git-v2-...","vaultKvSignature":"VAULT-KV-SIG-ROTATED-..."}}
  ```

---

## 🔗 ¿Dónde seguir?

- 📘 **[Volver a la Guía Explicada para Dummies (`docs/HOWTO-DUMMIES.md`)](HOWTO-DUMMIES.md)**: Con la historia del hotel de alta seguridad, diagramas y guía visual de la consola web.
- 🏠 **[Volver al `README.md` principal](../README.md)**: Resumen de arquitectura, tabla de red y estructura del proyecto.

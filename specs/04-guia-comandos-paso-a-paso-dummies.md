# Spec 04: Guía de Comandos 1 por 1 para Dummies (`docs/PASO-A-PASO-COMANDOS.md`)

- **Status**: Implemented
- **Date**: 2026-10-19
- **Author**: Antigravity & User

---

## 1. Context & Objective

Aunque el repositorio ya cuenta con una visión general en `README.md` y una guía conceptual e interactiva en `docs/HOWTO-DUMMIES.md`, un usuario principiante ("dummy") que quiera levantar el laboratorio comando a comando —o comprender exactamente qué órdenes se ejecutan por debajo en cada máquina virtual para dejar todo montado desde cero— necesita un manual secuencial **1 por 1**, sin pasos implícitos ni saltos mágicos.

El objetivo de esta especificación es crear un documento exclusivo `docs/PASO-A-PASO-COMANDOS.md` (y enlazarlo de forma prominente desde `README.md` y `docs/HOWTO-DUMMIES.md`) que guíe al lector comando por comando en dos modalidades complementarias:
1. **Recorrido A — Modo Docker Paso a Paso (Contenedor a Contenedor)**: cómo construir las imágenes y levantar cada una de las 4 VMs (`vm-db`, `vm-vault`, `vm-ansible`, `vm-app`) una por una desde el Host, comprobando que cada pieza funciona antes de encender la siguiente.
2. **Recorrido B — Modo Manual "Destripado" (Comando a Comando dentro de cada VM)**: la secuencia exacta e individual de comandos que configuran el sistema completo por dentro (creación de roles y tablas en PostgreSQL, inicialización y desellado de Vault, activación de motores `database` y `approle`, creación de políticas y roles dinámicos/estáticos, obtención y despliegue de `role_id` / `secret_id` con Ansible, arranque del `vault agent` y lanzamiento de la aplicación Java Spring Boot).

---

## 2. Requirements & Acceptance Criteria

### 2.1. Estructura de Ficha por Comando ("Formato para Dummies")
Cada comando numerado (`Paso 1`, `Paso 2`, ..., `Paso N`) en ambos recorridos debe incluir una ficha estandarizada de 4 elementos:
- **📍 Dónde se ejecuta**: Indicando claramente si es en la terminal de tu ordenador (`Host: PowerShell / Bash`) o dentro de una máquina concreta (`Dentro de vm-db`, `Dentro de vm-vault`, `Dentro de vm-ansible`, `Dentro de vm-app`).
- **💻 Comando exacto copiable**: Bloque de código listo para copiar y pegar (incluyendo `MSYS_NO_PATHCONV=1` cuando aplique en Git Bash para Windows).
- **🧠 ¿Qué hace este comando? (Explicación para Dummies)**: Explicación en lenguaje cotidiano y sin dar nada por sentado sobre qué hace cada flag o parámetro.
- **✅ Salida esperada (¿Cómo sé que ha funcionado?)**: Ejemplo literal de lo que debe devolver la terminal para confirmar el éxito antes de pasar al siguiente comando.

### 2.2. Recorrido A: Montaje Paso a Paso con Docker Compose (1 por 1 desde el Host)
Secuencia ordenada desde cero hasta tener el dashboard y la rotación funcionando:
1. **Paso A.1 — Comprobar que Docker está encendido (`docker info` / `docker compose version`)**.
2. **Paso A.2 — Limpiar cualquier resto anterior (`docker compose down -v`)**.
3. **Paso A.3 — Construir las imágenes de las máquinas (`docker compose build`)**.
4. **Paso A.4 — Encender solo la Máquina 1: Base de Datos PostgreSQL (`docker compose up -d vm-db`)**.
5. **Paso A.5 — Verificar que PostgreSQL está listo y con la tabla de auditoría creada (`docker inspect` health + `psql -c "\du"` y `\dt`)**.
6. **Paso A.6 — Encender la Máquina 2: Servidor HashiCorp Vault (`docker compose up -d vm-vault`)**.
7. **Paso A.7 — Verificar que Vault se ha inicializado, desellado y configurado (`docker logs vm-vault` + `vault status`)**.
8. **Paso A.8 — Ejecutar la Máquina 3: Nodo Ansible Provisioner (`docker compose up vm-ansible` / verificación de entrega de AppRole)**.
9. **Paso A.9 — Encender la Máquina 4: Servidor de Aplicación Spring Boot + Vault Agent (`docker compose up -d vm-app`)**.
10. **Paso A.10 — Verificar los ficheros renderizados por Vault Agent en RAM (`db-dynamic.properties` y `db-static.properties`)**.
11. **Paso A.11 — Verificar la API REST y abrir la consola web animada (`curl http://localhost:18080/api/pilot/state`)**.
12. **Paso A.12 — Ejecutar los scripts de validación automática (`bash scripts/verify-pilot.sh` y `bash scripts/verify-ui.sh`)**.

### 2.3. Recorrido B: Montaje Manual "Destripado" (Todos los Comandos Internos 1 por 1)
Para quien quiera entender o ejecutar manualmente cada comando que ocurre detrás del telón en las 4 máquinas virtuales:
- **Fase 1 (En `vm-db` - PostgreSQL)**:
  - Comando 1: Crear el rol `vault_admin` con permisos `CREATEROLE` para que Vault pueda administrar cuentas.
  - Comando 2: Crear el rol de grupo `pilot_app_group` y el usuario fijo `app_static_user`.
  - Comando 3: Crear la tabla `public.connection_audit_log` y dar permisos a `pilot_app_group`.
- **Fase 2 (En `vm-vault` - Inicialización y Desellado de la Cámara Acorazada)**:
  - Comando 4: Arrancar el proceso `vault server -config=/vault/config/config.hcl`.
  - Comando 5: Inicializar Vault (`vault operator init -key-shares=1 -key-threshold=1 -format=json`) para obtener la llave maestra (`Unseal Key`) y el `Root Token`.
  - Comando 6: Abrir la puerta acorazada (`vault operator unseal <UNSEAL_KEY>`).
  - Comando 7: Autenticarse como administrador (`export VAULT_TOKEN=<ROOT_TOKEN>`).
- **Fase 3 (En `vm-vault` - Configuración de Motores de Secretos, Políticas y Roles)**:
  - Comando 8: Activar el motor de bases de datos (`vault secrets enable database`).
  - Comando 9: Conectar Vault con PostgreSQL (`vault write database/config/postgres-pilot ...`).
  - Comando 10: Crear el Rol Dinámico con caducidad de 60s (`vault write database/roles/postgres-dynamic-role ...`).
  - Comando 11: Crear el Rol Estático con rotación automática cada 60s (`vault write database/static-roles/postgres-static-role ...`).
  - Comando 12: Cargar la política de mínimo privilegio (`vault policy write app-db-policy /vault/policies/app-db-policy.hcl`).
  - Comando 13: Activar el método de acceso para máquinas (`vault auth enable approle`).
  - Comando 14: Crear el AppRole de la aplicación (`vault write auth/approle/role/spring-app-role ...`).
- **Fase 4 (En `vm-ansible` - Extracción y Entrega de Identidad AppRole por SSH)**:
  - Comando 15: Pedir a Vault el identificador público `role_id` (`vault read -field=role_id auth/approle/role/spring-app-role/role-id`).
  - Comando 16: Pedir a Vault el pase secreto de un solo uso `secret_id` (`vault write -f -field=secret_id auth/approle/role/spring-app-role/secret-id`).
  - Comando 17: Lanzar el playbook de Ansible (`ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml`) que deposita `/etc/vault.d/role_id` y `/etc/vault.d/secret_id` con permisos `0600` en `vm-app`.
- **Fase 5 (En `vm-app` - Vault Agent y Aplicación Java 21 Spring Boot)**:
  - Comando 18: Arrancar `vault agent -config=/etc/vault.d/vault-agent.hcl` para que haga Auto-Auth, borre el `secret_id` y empiece a escribir `/run/secrets/db-dynamic.properties` y `/run/secrets/db-static.properties`.
  - Comando 19: Arrancar el microservicio Java (`java -jar /opt/app/app.jar`) que lee esos ficheros y levanta el dashboard en el puerto `8080` (`18080` en el Host).
- **Fase 6 (Comandos de Prueba de Rotación Manual 1 por 1)**:
  - Comando 20: Pedir un usuario dinámico nuevo por CLI (`vault read database/creds/postgres-dynamic-role`).
  - Comando 21: Forzar el cambio de contraseña del usuario estático por CLI (`vault write -f database/rotate-role/postgres-static-role`).
  - Comando 22: Comprobar en PostgreSQL la tabla de auditoría (`SELECT * FROM public.connection_audit_log ORDER BY id DESC LIMIT 10;`).

### 2.4. Integración y Enlaces en la Documentación Existente
- En `README.md`: Añadir un enlace destacado en las secciones de inicio rápido y arquitectura apuntando a `docs/PASO-A-PASO-COMANDOS.md`.
- En `docs/HOWTO-DUMMIES.md`: Añadir una nota/enlace directo al inicio y en la sección de Puesta en Marcha redirigiendo a `docs/PASO-A-PASO-COMANDOS.md` para quienes quieran ejecutar o inspeccionar los comandos 1 por 1.

---

## 3. Technical Design & Architecture

### 3.1. Diagrama de Secuencia Numerado (Mapa de los 22 Comandos)
`docs/PASO-A-PASO-COMANDOS.md` abrirá con un diagrama Mermaid (`flowchart TD` o `sequenceDiagram`) donde cada flecha tenga el número exacto del comando (`[Cmd 1]`, `[Cmd 5]`, `[Cmd 17]`, etc.), sirviendo como mapa visual para que el lector sepa en qué punto exacto del montaje se encuentra en cada comando.

### 3.2. Archivos Afectados
1. **Nuevo archivo**: `docs/PASO-A-PASO-COMANDOS.md`
2. **Modificación**: `README.md` (añadir referencias y enlaces a `docs/PASO-A-PASO-COMANDOS.md`)
3. **Modificación**: `docs/HOWTO-DUMMIES.md` (añadir referencias y enlaces a `docs/PASO-A-PASO-COMANDOS.md`)

---

## 4. Implementation Plan (Tasks)

- [x] **Task 1**: Crear `docs/PASO-A-PASO-COMANDOS.md` con el mapa visual Mermaid numerado, el **Recorrido A** (12 pasos Docker 1 por 1 desde el Host con fichas completas) y el **Recorrido B** (22 comandos internos 1 por 1 en las 4 VMs con fichas completas).
- [x] **Task 2**: Actualizar `README.md` y `docs/HOWTO-DUMMIES.md` para enlazar de forma visible a `docs/PASO-A-PASO-COMANDOS.md`.
- [x] **Task 3**: Verificar que todos los enlaces relativos funcionan, que los bloques de código y diagramas Mermaid están bien formados y que las pruebas `scripts/verify-pilot.sh` y `scripts/verify-ui.sh` siguen pasando.

---

## 5. Verification Plan

1. Comprobar existencia y estructura completa de `docs/PASO-A-PASO-COMANDOS.md` (Recorrido A con 12 pasos y Recorrido B con 22 comandos, todos con ficha de 4 puntos: Dónde, Comando, Explicación para Dummies, Salida esperada).
2. Comprobar que `README.md` y `docs/HOWTO-DUMMIES.md` enlazan correctamente a `docs/PASO-A-PASO-COMANDOS.md`.
3. Ejecutar `bash scripts/verify-pilot.sh` y `bash scripts/verify-ui.sh` para garantizar que no se ha roto nada en el repositorio.

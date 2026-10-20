# Spec 06: Actualización Integral y Sincronización de Documentación para la Arquitectura de 6 VMs (Gitea + Spring Cloud Config + Vault + Ansible + PostgreSQL)

- **Status**: Implemented
- **Depends on**: SPEC 01, SPEC 02, SPEC 03, SPEC 04, SPEC 05
- **Date**: 2026-10-20
- **Objective**: Actualizar y sincronizar de forma exhaustiva `README.md`, `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md` para que todas las analogías, diccionarios, diagramas Mermaid de secuencia/estados, recorridos paso a paso en orden cronológico y recetarios de terminal reflejen sin inconsistencias la arquitectura completa de 6 máquinas virtuales (`vm-db`, `vm-vault`, `vm-git`, `vm-config-server`, `vm-ansible`, `vm-app`).

---

## 1. Scope

### Qué entra en el alcance (In Scope)
1. **Revisión y sincronización de `README.md`**:
   - Asegurar que los enlaces rápidos, descripciones de los recorridos (actualizando referencias de "22 comandos" al total cronológico real de las 6 VMs), tabla de puertos/URLs (`:18080`, `:13000`, `:18888`, `:18200`, `:15432`) y árbol del proyecto incluyan `specs/06-actualizacion-integral-documentacion.md`.
2. **Actualización profunda de `docs/HOWTO-DUMMIES.md` (Arquitectura de 6 VMs)**:
   - **Título, índice y analogía del Hotel (Sección 1)**: Ampliar la analogía para explicar también el rol de **Gitea (`vm-git`)** como el "Libro de Normas del Hotel" y **Spring Cloud Config Server (`vm-config-server`)** como el "Tablón Central de Anuncios" que combina normas de Git con secretos KV v2 de Vault y avisa a Spring Boot (`@RefreshScope`) sin reiniciar.
   - **Diccionario y Comparativa (Secciones 2 y 3)**: Actualizar el título a **Los 9 conceptos clave** (incluyendo `KV v2`, `Gitea Git Server`, `Spring Cloud Config Server` y `@RefreshScope`) y añadir una tabla comparativa de los **3 canales en caliente del piloto** (`DYNAMIC SQL Lease`, `STATIC SQL Role`, `SPRING CLOUD CONFIG + VAULT KV v2`).
   - **Diagramas Mermaid (Sección 4)**:
     - **4.1**: Mapa topológico de las 6 VMs (con índice actualizado).
     - **4.2**: Diagrama de secuencia `sequenceDiagram` completo del arranque y negociación inicial con las **6 máquinas** (`vm-db`, `vm-git`, `vm-vault`, `vm-config-server`, `vm-app`, `vm-ansible`).
     - **4.3**: Diagrama de secuencia `sequenceDiagram` con los **3 flujos de recarga en caliente**: Caso A (Rotación Dinámica SQL), Caso B (Rotación Estática SQL) y Caso C (Commit en Gitea + Rotación KV v2 en Vault + `ContextRefresher.refresh()` `@RefreshScope`).
     - **4.4**: Diagrama de estados `stateDiagram-v2` incluyendo tanto el ciclo de vida del pool HikariCP como el ciclo `@RefreshScope` de Spring Cloud Config.
   - **Puesta en marcha, Guía de la Consola Web y Recetario de Terminal (Secciones 5, 6, 7 y 8)**:
     - Actualizar el Paso 5.3 y 5.4 para describir el arranque de los **6 contenedores** en orden real y las 3 URLs accesibles desde el navegador (`http://localhost:18080`, `http://localhost:13000`, `http://localhost:18888/vault-rotation-pilot/default`).
     - Actualizar la Sección 6 detallando los **6 nodos SVG**, los 5 colores de partículas animadas (incluyendo las rosas de Gitea/Config Server), los 6 pasos del botón `▶ Simular Flujo Completo` y el botón `🔄 Commit en Gitea + Refresh Spring Cloud (@RefreshScope)`.
     - Ampliar la Sección 7 ("Caja de Cristal") con subsecciones para inspeccionar Vault KV v2 (`secret/git-credentials` y `secret/vault-rotation-pilot`), el repositorio Gitea (`vm-git`), el JSON compuesto de `vm-config-server` y el disparo por CLI de `POST /api/pilot/config/refresh`.
     - Ampliar la Sección 8 (FAQ / Troubleshooting) con preguntas sobre puertos `13000`/`18888`, credenciales de Gitea en Vault y funcionamiento de `@RefreshScope`.
3. **Reestructuración cronológica completa de `docs/PASO-A-PASO-COMANDOS.md`**:
   - **Recorrido A — Modo Docker Paso a Paso (16 comandos desde el PC en orden cronológico real)**:
     - `Paso A.1`: Comprobar que Docker está despierto.
     - `Paso A.2`: Limpiar montaje antiguo (`docker compose down -v`).
     - `Paso A.3`: Construir las imágenes de las máquinas virtuales (`docker compose build`).
     - `Paso A.4`: Encender Máquina 1 — Base de Datos PostgreSQL (`vm-db`).
     - `Paso A.5`: Verificar usuarios y tabla en `vm-db`.
     - `Paso A.6`: Encender Máquina 2 — Servidor HashiCorp Vault (`vm-vault`).
     - `Paso A.7`: Verificar `vault status` y secretos KV v2 iniciales en `vm-vault`.
     - `Paso A.8`: Encender Máquina 3 — Servidor Git Gitea (`vm-git`).
     - `Paso A.9`: Verificar repositorio `pilot-admin/pilot-config` y `vault-rotation-pilot.yml` en Gitea (`:13000`).
     - `Paso A.10`: Encender Máquina 4 — Spring Cloud Config Server (`vm-config-server`) en espera de AppRole.
     - `Paso A.11`: Encender Máquina 5 — Aplicación Spring Boot (`vm-app`) en espera de AppRole.
     - `Paso A.12`: Ejecutar Máquina 6 (`vm-ansible`) para inyectar AppRole por SSH en `vm-config-server` y `vm-app`.
     - `Paso A.13`: Verificar credenciales Git en `vm-config-server` y respuesta del Composite Backend (`:18888`).
     - `Paso A.14`: Verificar ficheros `/run/secrets/db-dynamic.properties` y `db-static.properties` en `vm-app`.
     - `Paso A.15`: Verificar API `/api/pilot/state` y abrir la consola web animada (`:18080`).
     - `Paso A.16`: Ejecutar suites de verificación `verify-ui.sh` y `verify-pilot.sh`.
   - **Recorrido B — Modo Manual "Destripado" (28 comandos internos en orden cronológico estricto + Diagrama de Secuencia actualizado)**:
     - Actualizar el diagrama `sequenceDiagram` inicial con las 6 máquinas y los **28 comandos** numerados en el orden real en que ocurren:
       - **Fase 1 (`vm-db`)**: Comandos 1 a 3 (roles y tabla en PostgreSQL).
       - **Fase 2 (`vm-git`)**: Comandos 4 y 5 (arrancar Gitea, verificar usuario `pilot-admin` y commit inicial de `vault-rotation-pilot.yml`).
       - **Fase 3 (`vm-vault`)**: Comandos 6 a 9 (arrancar, inicializar, desellar y login root en Vault).
       - **Fase 4 (`vm-vault`)**: Comandos 10 a 18 (habilitar `database/`, configurar conexión y roles dinámico/estático, habilitar `secret/` KV v2, guardar `secret/git-credentials` y `secret/vault-rotation-pilot`, cargar política `app-db-policy` y crear AppRole `spring-app-role`).
       - **Fase 5 (`vm-ansible` -> `vm-config-server` y `vm-app`)**: Comandos 19 a 21 (obtener `role_id`, generar `secret_id` y ejecutar playbook SSH sobre ambas máquinas).
       - **Fase 6 (`vm-config-server` y `vm-app`)**: Comandos 22 a 25 (verificar `vault agent` y credenciales Git en `vm-config-server`, consultar `:18888/vault-rotation-pilot/default`, verificar `vault agent` y proceso Java en `vm-app`).
       - **Fase 7 (Pruebas de Rotación y Hot-Reload en vivo)**: Comandos 26 a 28 (generar credencial dinámica SQL, forzar rotación estática SQL y disparar commit en Gitea + rotación KV v2 + `@RefreshScope` vía `POST /api/pilot/config/refresh`).

### Qué queda fuera del alcance (Out of Scope)
- Modificar código fuente Java, scripts de infraestructura o configuración de contenedores (todo el código e infraestructura ya quedó implementado y verificado en SPEC 05).
- Crear ficheros de documentación adicionales fuera de `README.md`, `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md`.

---

## 2. Data Model

Esta especificación es exclusivamente documental y no introduce cambios en modelos de datos, endpoints ni esquemas SQL. Documenta fielmente las estructuras introducidas hasta la SPEC 05:
- Las **6 máquinas virtuales (contenedores)** en `172.29.0.0/24` (`vm-vault` `.10`, `vm-db` `.20`, `vm-app` `.30`, `vm-ansible` `.40`, `vm-git` `.50`, `vm-config-server` `.60`).
- Los **16 pasos del Recorrido A** y los **28 comandos internos del Recorrido B** en `docs/PASO-A-PASO-COMANDOS.md`.

---

## 3. Implementation Plan

1. **Step 1 — Actualizar `docs/HOWTO-DUMMIES.md` al completo para las 6 VMs**:
   - Actualizar título, introducción, índice, analogía del Hotel, tabla de los 9 conceptos clave y comparativa de los 3 canales dinámicos/recargables.
   - Actualizar los diagramas Mermaid `4.2` (secuencia de arranque de 6 VMs), `4.3` (secuencia de rotación dinámica, estática y `@RefreshScope`) y `4.4` (diagrama de estados).
   - Actualizar las secciones 5 (Puesta en marcha de las 6 VMs), 6 (Guía visual de la consola de 6 nodos y 4 tarjetas), 7 (Recetario de terminal con Gitea, Vault KV v2 y Config Server) y 8 (FAQ / Troubleshooting).
2. **Step 2 — Reestructurar `docs/PASO-A-PASO-COMANDOS.md` en orden cronológico (16 pasos en Recorrido A + 28 comandos en Recorrido B)**:
   - Actualizar el diagrama Mermaid `sequenceDiagram` de cabecera con las 6 VMs y los 28 comandos en orden cronológico.
   - Reescribir el **Recorrido A** con los 16 pasos ordenados desde `vm-db` hasta `verify-pilot.sh` / `verify-ui.sh`.
   - Reescribir el **Recorrido B** integrando los 28 comandos internos en 7 fases cronológicas (BD -> Gitea -> Apertura Vault -> Motores DB + KV v2 + AppRole -> Ansible SSH a ambas VMs -> Config Server + App -> Pruebas de rotación y `@RefreshScope`).
3. **Step 3 — Sincronizar `README.md` y verificar enlaces y coherencia**:
   - Actualizar `README.md` para reflejar la descripción de los 16 pasos / 28 comandos de `docs/PASO-A-PASO-COMANDOS.md` y listar `SPEC 06` en el árbol y sección de especificaciones.
   - Ejecutar `scripts/verify-ui.sh` y comprobar que no quede ninguna mención obsoleta a "4 máquinas" o "22 comandos" en `README.md`, `docs/HOWTO-DUMMIES.md` ni `docs/PASO-A-PASO-COMANDOS.md`.

---

## 4. Acceptance Criteria

- [x] Ninguno de los ficheros `README.md`, `docs/HOWTO-DUMMIES.md` ni `docs/PASO-A-PASO-COMANDOS.md` contiene referencias obsoletas a "4 máquinas", "4 contenedores", "3 tarjetas" o "22 comandos".
- [x] `docs/HOWTO-DUMMIES.md` incluye los 4 diagramas Mermaid (`4.1`, `4.2`, `4.3`, `4.4`) actualizados con las 6 máquinas (`vm-db`, `vm-vault`, `vm-git`, `vm-config-server`, `vm-ansible`, `vm-app`) y el flujo de `@RefreshScope`.
- [x] `docs/PASO-A-PASO-COMANDOS.md` contiene el **Recorrido A** con los **16 pasos** cronológicos de Docker y el **Recorrido B** con el diagrama de secuencia y las fichas completas de los **28 comandos internos** en orden cronológico real.
- [x] Todos los bloques de comandos en `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md` incluyen `MSYS_NO_PATHCONV=1` cuando invocan rutas POSIX con `docker exec`.
- [x] `bash scripts/verify-ui.sh` termina con `EXIT 0`.

---

## 5. Decisions Taken and Discarded

- **Actualizar y unificar los 3 documentos existentes frente a crear un cuarto documento suelto (Elegida 1A)**: Mantener toda la documentación centralizada en `README.md`, `docs/HOWTO-DUMMIES.md` y `docs/PASO-A-PASO-COMANDOS.md` evita duplicidades y garantiza que un lector nuevo tenga una única fuente de verdad coherente de principio a fin.
- **Orden cronológico real en Recorrido A (16 pasos) y Recorrido B (28 comandos) frente a dejar Spec 05 como anexo final (Elegida 2A)**: Como `vm-app` importa configuración de `vm-config-server` al arrancar y `vm-ansible` aprovisiona tanto `vm-config-server` como `vm-app`, explicar los pasos en su orden cronológico real evita confusiones al levantar los contenedores uno a uno.
- **Actualizar todos los diagramas de secuencia y estado en `docs/HOWTO-DUMMIES.md` (Elegida 3A)**: Los diagramas Mermaid son la pieza visual clave para entender cómo conviven la rotación de base de datos con la recarga de propiedades de Gitea + Vault KV v2.

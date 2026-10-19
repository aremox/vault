# SPEC 03 — Documentación README y guía How-To para Dummies con gráficos Mermaid

> **Status:** Implemented
> **Depends on:** SPEC 01, SPEC 02
> **Date:** 2026-10-19
> **Objective:** Documentar el piloto mediante un `README.md` estructurado en la raíz y un manual exhaustivo paso a paso en `docs/HOWTO-DUMMIES.md` con diagramas gráficos Mermaid que expliquen sin ambigüedades los conceptos, la arquitectura, el arranque, el uso de la consola web y la verificación manual.

---

## Por qué existe esta spec

El piloto integra múltiples tecnologías (contenedores simulando VMs en subred fija, HashiCorp Vault Server con almacenamiento en disco, AppRole, Ansible sobre SSH, Vault Agent con plantillas `.ctmpl`, recarga en caliente de `HikariCP` en Spring Boot y PostgreSQL). Para que cualquier persona pueda entender qué ocurre por dentro y ejecutar o auditar el piloto desde cero sin conocimientos previos de Vault o Ansible, se separa un `README.md` claro en la raíz y una guía didáctica completa en `docs/HOWTO-DUMMIES.md`.

---

## Alcance

**Dentro del alcance:**

- Creación de `docs/HOWTO-DUMMIES.md` redactado en lenguaje didáctico ("para dummies", con analogías sencillas y sin pasos implícitos) que incluya:
  1. **Diccionario visual de conceptos sin jerga:** qué problema resuelve Vault, qué es `init` y `unseal`, cómo funciona AppRole (`role_id` + `secret_id` y por qué interviene Ansible), diferencia entre Secreto Dinámico (usuario efímero) y Secreto Estático Rotado (usuario fijo con cambio de contraseña), qué hace `vault-agent` y por qué Spring Boot recrea el pool `HikariCP`.
  2. **Gráficos Mermaid nativos de GitHub:**
     - `flowchart`: topología detallada de la red `172.29.0.0/24`, puertos, volúmenes y procesos internos de las 4 VMs (`vm-ansible`, `vm-vault`, `vm-app`, `vm-db`).
     - `sequenceDiagram` (Fase de Arranque y Negociación): desde `docker compose up` hasta la inyección SSH con Ansible, autenticación de `vault-agent` y primer renderizado de `/run/secrets/*.properties`.
     - `sequenceDiagram` (Fase de Rotación Dinámica vs Estática): cómo expira el TTL de 60s o se rota la clave estática y cómo `RotatableDataSourceManager` sustituye el pool de conexiones sin perder peticiones.
     - `stateDiagram-v2`: ciclo de vida de una credencial y del pool de conexiones `HikariCP`.
  3. **Guía paso a paso desde cero:** prerrequisitos, clonado, levantamiento en Windows (PowerShell / Git Bash), Linux y macOS, y comprobación de salud de cada contenedor.
  4. **Manual visual de la Consola Web (`http://localhost:18080`):** explicación de cada panel, significado de los colores de las partículas animadas, cómo mostrar/ocultar contraseñas y qué ocurre al pulsar cada botón de acción.
  5. **Recetario de inspección en terminal ("Caja de cristal"):** comandos exactos copiar-y-pegar para inspeccionar Vault, relanzar Ansible, ver los ficheros en `/etc/vault.d/` y `/run/secrets/`, seguir los logs de Spring Boot y consultar PostgreSQL en directo.
  6. **Preguntas Frecuentes (FAQ) y Troubleshooting:** solución a conflictos de subred Docker, puertos ocupados, errores de CRLF en Windows o contenedores que tardan en arrancar.
- Actualización de `README.md` en la raíz del repositorio con resumen ejecutivo, diagrama Mermaid de arquitectura general, árbol de ficheros del proyecto, arranque rápido en 3 comandos y enlace destacado a `docs/HOWTO-DUMMIES.md`.

**Fuera del alcance (para futuras specs):**

- Modificaciones en el código Java, scripts de infraestructura o configuración de contenedores.
- Generación de vídeos o capturas binarias pesadas (`.mp4` / `.gif`).

---

## Modelo de datos

Esta funcionalidad no introduce nuevas estructuras de datos ni modifica esquemas existentes; únicamente añade y actualiza artefactos de documentación Markdown (`README.md` y `docs/HOWTO-DUMMIES.md`).

---

## Plan de implementación

1. **Crear `docs/HOWTO-DUMMIES.md` con la explicación conceptual para dummies y los diagramas Mermaid de arquitectura, secuencia y estados.**
   Redactar la primera mitad de `docs/HOWTO-DUMMIES.md` incluyendo el índice navegable, las analogías de cada componente, la tabla comparativa Dinámico vs Estático y los 4 diagramas Mermaid (`flowchart`, 2 `sequenceDiagram` y 1 `stateDiagram-v2`).

2. **Completar `docs/HOWTO-DUMMIES.md` con el tutorial paso a paso, guía de la consola web, recetario CLI y sección de Troubleshooting/FAQ.**
   Añadir en `docs/HOWTO-DUMMIES.md` los pasos detallados de ejecución, explicación de la interfaz `http://localhost:18080`, comandos de verificación manual en los 4 contenedores y tabla de diagnóstico de problemas comunes.

3. **Actualizar `README.md` en la raíz del proyecto enlazando a `docs/HOWTO-DUMMIES.md`.**
   Reescribir `README.md` con diagrama de arquitectura Mermaid, árbol comentado de directorios, guía rápida de ejecución y acceso directo a `docs/HOWTO-DUMMIES.md` y a las specs `SPEC 01`, `SPEC 02` y `SPEC 03`.

---

## Criterios de aceptación

- [x] Existe el fichero `docs/HOWTO-DUMMIES.md` con índice navegable y secciones de conceptos para dummies, puesta en marcha paso a paso, guía de la consola web, recetario de comandos CLI y Troubleshooting/FAQ.
- [x] `docs/HOWTO-DUMMIES.md` contiene al menos 4 diagramas Mermaid válidos (`flowchart`, dos `sequenceDiagram` y un `stateDiagram-v2`) sin errores de sintaxis.
- [x] Todos los comandos, rutas de ficheros (`/etc/vault.d/role_id`, `/run/secrets/db-dynamic.properties`, `/run/secrets/db-static.properties`), nombres de roles (`spring-app-role`, `postgres-dynamic-role`, `postgres-static-role`, `app_static_user`) e IPs (`172.29.0.10`, `172.29.0.20`, `172.29.0.30`, `172.29.0.40`) en `docs/HOWTO-DUMMIES.md` y `README.md` coinciden exactamente con la implementación real del piloto.
- [x] `README.md` incluye árbol de directorios del proyecto, instrucciones de arranque rápido y enlace funcional a `docs/HOWTO-DUMMIES.md`.

---

## Decisiones

- **Sí:** Separar un `README.md` conciso en la raíz y una guía exhaustiva en `docs/HOWTO-DUMMIES.md`. Mantiene la portada del repositorio limpia para consulta rápida y ofrece un manual profundo sin recortes para quien quiera aprender cada detalle.
- **Sí:** Usar diagramas **Mermaid nativos de GitHub** (`flowchart`, `sequenceDiagram`, `stateDiagram-v2`). Se renderizan automáticamente en la interfaz de GitHub, son versionables como texto y siempre permanecen sincronizados con el código.
- **No:** Incluir capturas estáticas pesadas que queden desactualizadas al cambiar estilos o IPs.

---

## Qué **no** incluye esta spec

- Cambios funcionales en los contenedores (`vm-vault`, `vm-db`, `vm-app`, `vm-ansible`) ni en el código de la aplicación Spring Boot.
- Traducción de la documentación a otros idiomas distintos del castellano.

Cada uno de esos puntos, si se aborda en el futuro, irá en su propia spec independiente.

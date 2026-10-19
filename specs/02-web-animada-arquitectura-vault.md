# SPEC 02 — Consola web animada de arquitectura, artefactos y rotación de claves en vivo

> **Status:** Approved
> **Depends on:** SPEC 01
> **Date:** 2026-10-19
> **Objective:** Incorporar en la aplicación Spring Boot (`vm-app`) una consola web interactiva con animaciones SVG de movimiento que visualice en tiempo real la topología de contenedores VM, el intercambio de artefactos (`role_id`, `secret_id`, tokens, leases, ficheros `.properties`) y la rotación de claves dinámicas y estáticas contra PostgreSQL.

---

## Por qué existe esta spec

En `SPEC 01` la validación del piloto se realiza por línea de comandos (`scripts/verify-pilot.sh`) e inspección de logs/tablas SQL. Para demostraciones técnicas y observabilidad inmediata, resulta mucho más claro disponer de una interfaz visual en vivo donde se aprecie cómo viajan los artefactos entre `vm-ansible`, `vm-vault`, `vm-app` (`vault-agent` + `Spring Boot`) y `vm-db`, qué credenciales están activas en cada instante y cómo cambian los usuarios efímeros, las contraseñas rotadas y los PIDs de conexión en PostgreSQL sin caída del servicio.

---

## Alcance

**Dentro del alcance:**

- Exposición del servidor web embebido de Spring Boot en `vm-app` (`172.29.0.30:8080`) mapeado al puerto `18080` del host (`http://localhost:18080`).
- Ampliación de `RotatableDataSourceManager` y `DbRotationProbeService` para exponer metadatos en vivo de los artefactos en `/etc/vault.d/` y `/run/secrets/`, contadores de rotación, marcas de tiempo, hash SHA-256 y la contraseña actual (con soporte de enmascarado/desenmascarado en la UI).
- Nuevo servicio `VaultControlService` y controlador `PilotDashboardController` con endpoints REST:
  - `GET /api/pilot/state`: estado completo de los 4 nodos VM, artefactos AppRole (`role_id`, `secret_id`), credenciales activas (`DYNAMIC` y `STATIC`), sesiones en `pg_stat_activity` y últimos registros de `public.connection_audit_log`.
  - `POST /api/pilot/rotate/static`: fuerza la rotación inmediata del rol estático en Vault (`database/rotate-role/postgres-static-role`) y refresca `vault-agent`.
  - `POST /api/pilot/rotate/dynamic`: fuerza la revocación/renovación del lease dinámico en Vault para observar al instante el cambio de usuario efímero SQL.
- Frontend SPA ligero en `app/src/main/resources/static/` (`index.html`, `styles.css`, `app.js`) con:
  - **Mapa de arquitectura SVG animado (`172.29.0.0/24`):** representación visual de `vm-ansible` (`172.29.0.40`), `vm-vault` (`172.29.0.10`), `vm-app` (`172.29.0.30` con subcomponentes `sshd`, `vault-agent`, `/run/secrets/*.properties`, `Spring Boot + HikariCP`) y `vm-db` (`172.29.0.20`).
  - **Efectos de movimiento de paquetes y llaves:** partículas animadas desplazándose por las rutas SVG para representar el envío SSH de `role_id` + `secret_id`, la negociación AppRole, la escritura de plantillas `.ctmpl`, los latidos SQL cada 5s y ondas/destellos de transición cuando rota una clave o se recrea un pool `HikariCP`.
  - **Panel de artefactos y claves con toggle mostrar/ocultar:** tarjetas comparativas para el canal Dinámico y el canal Estático mostrando usuario SQL, contraseña (oculta por defecto con botón de visualización en claro), hash SHA-256, `pg_backend_pid` actual vs anterior y tiempo desde la última rotación.
  - **Controles interactivos:** botones para disparar rotaciones bajo demanda y botón de reproducción paso a paso del flujo completo de negociación (`Ansible -> Vault -> Agent -> Spring Boot -> PostgreSQL`).
- Script de verificación `scripts/verify-ui.sh` para validar automáticamente los endpoints REST y la carga de la interfaz web.

**Fuera del alcance (para futuras specs):**

- Autenticación de usuarios o login en la consola web del piloto.
- Frameworks pesados de compilación frontend separada (Angular/React/Webpack con `node_modules`).
- Edición de políticas HCL de Vault desde el navegador.
- Persistencia histórica de métricas en Prometheus/Grafana.

---

## Modelo de datos

### 1. Respuesta JSON de estado en tiempo real (`GET /api/pilot/state`)

```json
{
  "timestamp": "2026-10-19T18:00:00Z",
  "subnet": "172.29.0.0/24",
  "nodes": {
    "ansible": { "ip": "172.29.0.40", "hostname": "vm-ansible", "status": "ONLINE" },
    "vault": { "ip": "172.29.0.10", "hostname": "vm-vault", "initialized": true, "sealed": false, "storage": "file" },
    "app": { "ip": "172.29.0.30", "hostname": "vm-app", "vaultAgentRunning": true },
    "db": { "ip": "172.29.0.20", "hostname": "vm-db", "database": "pilotdb", "status": "ONLINE" }
  },
  "approle": {
    "roleName": "spring-app-role",
    "roleId": "8f1d4e20-...",
    "secretIdPresent": true,
    "roleIdPermissions": "0600",
    "secretIdPermissions": "0600",
    "vaultTokenPresent": true
  },
  "credentials": {
    "dynamic": {
      "mode": "DYNAMIC",
      "filePath": "/run/secrets/db-dynamic.properties",
      "jdbcUrl": "jdbc:postgresql://172.29.0.20:5432/pilotdb",
      "username": "v-approle-postgres-xxxx-1792431428",
      "password": "A9f#kL29zP0qW8xR1mN4",
      "passwordHash": "acfc90fd3d05",
      "currentBackendPid": 487,
      "previousBackendPid": 94,
      "rotationCount": 2,
      "lastRotatedAt": "2026-10-19T17:59:10Z"
    },
    "static": {
      "mode": "STATIC",
      "filePath": "/run/secrets/db-static.properties",
      "jdbcUrl": "jdbc:postgresql://172.29.0.20:5432/pilotdb",
      "username": "app_static_user",
      "password": "R7v!mQ42pL9xK3wZ8nB1",
      "passwordHash": "f284a17e33",
      "currentBackendPid": 768,
      "previousBackendPid": 95,
      "rotationCount": 2,
      "lastRotatedAt": "2026-10-19T17:59:35Z"
    }
  },
  "activeSessions": [
    { "pid": 487, "username": "v-approle-postgres-xxxx-1792431428", "clientAddr": "172.29.0.30", "state": "idle" },
    { "pid": 768, "username": "app_static_user", "clientAddr": "172.29.0.30", "state": "idle" }
  ],
  "recentAudits": [
    { "id": 42, "credentialMode": "DYNAMIC", "dbUsername": "v-approle-postgres-xxxx-1792431428", "backendPid": 487, "executedAt": "2026-10-19T17:59:55Z" }
  ]
}
```

---

## Plan de implementación

1. **Habilitar Spring Web en `app/pom.xml`, `application.yml` y exponer el puerto `18080` en `docker-compose.yml`.**
   Añadir `spring-boot-starter-web` en `app/pom.xml`, configurar `server.port: 8080` en `app/src/main/resources/application.yml`, mapear el puerto `"18080:8080"` y montar `vault-bootstrap-data:/vault/bootstrap:ro` en el servicio `vm-app` dentro de `docker-compose.yml`.

2. **Ampliar `RotatableDataSourceManager` y `DbRotationProbeService` con telemetría de credenciales y rotaciones.**
   Actualizar `RotatableDataSourceManager.java` para registrar el estado detallado de cada pool (`username`, `password`, `passwordHash`, `rotationCount`, `lastRotatedAt`, `previousUsername`, `previousPasswordHash`) y `DbRotationProbeService.java` para almacenar el último `backend_pid` y el anterior por cada modo (`DYNAMIC` y `STATIC`), así como consultar `public.connection_audit_log` y `pg_stat_activity`.

3. **Implementar `VaultControlService` y `PilotDashboardController` con los endpoints de estado y rotación bajo demanda.**
   Crear `app/src/main/java/com/pilot/vault/service/VaultControlService.java` (lee metadatos de `/etc/vault.d/role_id`, `/etc/vault.d/secret_id`, consulta `http://172.29.0.10:8200/v1/sys/health` y permite disparar la rotación del rol estático y la renovación del lease dinámico en Vault) y `app/src/main/java/com/pilot/vault/controller/PilotDashboardController.java` (`GET /api/pilot/state`, `POST /api/pilot/rotate/static`, `POST /api/pilot/rotate/dynamic`).

4. **Construir la interfaz web animada (`index.html`, `styles.css`, `app.js`).**
   Crear en `app/src/main/resources/static/` la consola visual con diseño oscuro técnico:
   - Diagrama SVG de la subred `172.29.0.0/24` con los 4 contenedores VM, sus componentes internos (`sshd`, `vault-agent`, `/etc/vault.d`, `/run/secrets`, `HikariCP`) y partículas luminosas viajando por los trazos SVG en cada intercambio de artefactos o consulta SQL.
   - Paneles de inspección de artefactos y claves con botón mostrar/ocultar password, comparativa de cambio de usuario/clave/PID y animación de pulso al detectar una rotación en vivo.
   - Botones interactivos para forzar rotación estática, forzar rotación dinámica y lanzar la animación guiada paso a paso de toda la arquitectura.

5. **Crear el script de verificación `scripts/verify-ui.sh` y reconstruir el contenedor `vm-app`.**
   Escribir `scripts/verify-ui.sh` para comprobar que `http://localhost:18080/` sirve la web animada, que `GET /api/pilot/state` devuelve el JSON con las 4 VMs y ambos modos de credenciales, y que `POST /api/pilot/rotate/static` y `POST /api/pilot/rotate/dynamic` rotan efectivamente las claves en vivo.

---

## Criterios de aceptación

- [ ] Al acceder a `http://localhost:18080/`, el contenedor `vm-app` sirve la consola web con código HTTP `200`.
- [ ] El endpoint `GET http://localhost:18080/api/pilot/state` devuelve HTTP `200` con el estado de los 4 nodos (`172.29.0.10`, `172.29.0.20`, `172.29.0.30`, `172.29.0.40`), metadatos AppRole (`roleId`, permisos `0600`), credenciales `dynamic` y `static`, sesiones en `pg_stat_activity` e historial de `connection_audit_log`.
- [ ] La interfaz web renderiza el diagrama SVG de arquitectura con los 4 contenedores VM y animaciones de movimiento continuas y por evento para el flujo de artefactos (`role_id`, `secret_id`, token, `.properties` y queries SQL).
- [ ] Las tarjetas de credenciales muestran el `username`, el hash SHA-256, el `pg_backend_pid` y permiten alternar entre contraseña oculta (`••••••••`) y contraseña en claro mediante un botón mostrar/ocultar.
- [ ] Al pulsar "Forzar Rotación Estática" (`POST /api/pilot/rotate/static`), la contraseña y el hash de `app_static_user` cambian en la interfaz y se dispara la animación visual de rotación y recarga del pool `HikariCP`.
- [ ] Al pulsar "Forzar Rotación Dinámica" (`POST /api/pilot/rotate/dynamic`), se genera un nuevo usuario efímero `v-approle-postgres-...`, se actualiza la tarjeta dinámica en la web y cambia el `pg_backend_pid` en PostgreSQL sin errores.
- [ ] El script `scripts/verify-ui.sh` finaliza con código de salida `0`.

---

## Decisiones

- **Sí:** Servir el dashboard desde la propia aplicación **Spring Boot en `vm-app` (`http://localhost:18080`)**. Evita añadir un quinto contenedor y permite leer en memoria el estado exacto de `RotatableDataSourceManager` y los ficheros en `/run/secrets/` y `/etc/vault.d/`.
- **No:** Crear un proyecto Node/React/Angular separado. Añade complejidad de build innecesaria cuando HTML5 + CSS Keyframes + SVG + Vanilla JS ofrecen animaciones vectoriales a 60fps sin dependencias externas.
- **Sí:** Incluir un toggle mostrar/ocultar para la contraseña en claro además del hash SHA-256. Facilita comprobar visualmente en el piloto que el valor real de la clave cambia en cada rotación.
- **Sí:** Añadir botones de rotación manual (`POST /api/pilot/rotate/static` y `/api/pilot/rotate/dynamic`) además de la rotación automática cada 60 segundos. Permite demostrar el cambio de claves en cualquier momento sin tener que esperar al temporizador.

---

## Riesgos

| Riesgo | Mitigación |
| ------ | ---------- |
| Retardo entre la llamada a `database/rotate-role/postgres-static-role` en Vault y el re-renderizado de `/run/secrets/db-static.properties` por `vault-agent`. | El endpoint `POST /api/pilot/rotate/static` envía señal/recarga a `vault-agent` (o espera su ciclo de renderizado) y ejecuta `dataSourceManager.checkAndReloadIfNeeded()` para que la UI refleje la nueva clave en pocos segundos. |
| Puerto `8080` del host ocupado por otro contenedor (`rocky2` en `1-web_ansible-net`). | Mapear el puerto del contenedor `8080` al puerto `18080` en el host (`"18080:8080"` en `docker-compose.yml`). |

---

## Qué **no** incluye esta spec

- Autenticación o control de acceso en el dashboard web.
- Edición de políticas o configuración de roles de Vault desde la UI.
- Empaquetadores frontend externos (Webpack, Vite, npm).

Cada uno de esos puntos, si se aborda en el futuro, irá en su propia spec independiente.

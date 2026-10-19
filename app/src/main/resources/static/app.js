(() => {
    const secretState = {
        approleVisible: false,
        dynamicVisible: false,
        staticVisible: false,
        rawSecretId: "",
        rawDynamicPassword: "",
        rawStaticPassword: ""
    };

    let lastDynamicHash = null;
    let lastStaticHash = null;
    let lastAuditId = null;

    const paths = {
        ansibleVault: "M 155 185 L 155 265",
        ansibleApp: "M 280 115 L 370 115",
        agentVault: "M 280 330 L 370 250",
        agentFiles: "M 530 235 L 595 235",
        vaultDb: "M 280 375 C 540 430, 740 430, 885 340",
        appDbDyn: "M 790 165 L 885 195",
        appDbStat: "M 790 285 L 885 265"
    };

    function maskSecret(val) {
        if (!val) return "••••••••••••••••";
        if (val.length <= 6) return "••••••••";
        return val.substring(0, 4) + "••••••••••••" + val.substring(val.length - 3);
    }

    function setBanner(tag, message, flash = true) {
        const banner = document.getElementById("event-banner");
        const tagEl = document.getElementById("event-tag");
        const textEl = document.getElementById("event-text");
        tagEl.textContent = tag;
        textEl.textContent = message;
        if (flash) {
            banner.classList.remove("banner-flash");
            void banner.offsetWidth;
            banner.classList.add("banner-flash");
        }
    }

    function spawnPacketBurst(pathData, color, count = 4, durationMs = 1100) {
        const layer = document.getElementById("packet-burst-layer");
        if (!layer) return;

        for (let i = 0; i < count; i++) {
            setTimeout(() => {
                const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
                circle.setAttribute("r", "7");
                circle.setAttribute("fill", color);
                circle.setAttribute("filter", "url(#glow-cyan)");

                const anim = document.createElementNS("http://www.w3.org/2000/svg", "animateMotion");
                anim.setAttribute("dur", `${durationMs}ms`);
                anim.setAttribute("repeatCount", "1");
                anim.setAttribute("path", pathData);

                circle.appendChild(anim);
                layer.appendChild(circle);
                if (typeof anim.beginElement === "function") {
                    anim.beginElement();
                }

                setTimeout(() => {
                    if (circle.parentNode) {
                        circle.parentNode.removeChild(circle);
                    }
                }, durationMs + 100);
            }, i * 160);
        }
    }

    function highlightNode(nodeId, durationMs = 1400) {
        const el = document.getElementById(nodeId);
        if (!el) return;
        el.classList.add("node-active-glow");
        setTimeout(() => el.classList.remove("node-active-glow"), durationMs);
    }

    function flashCard(cardId) {
        const card = document.getElementById(cardId);
        if (!card) return;
        card.classList.remove("rotated-flash");
        void card.offsetWidth;
        card.classList.add("rotated-flash");
    }

    function renderSecretsVisibility() {
        const secretIdEl = document.getElementById("approle-secret-id");
        const dynPwdEl = document.getElementById("dyn-password");
        const statPwdEl = document.getElementById("stat-password");

        secretIdEl.textContent = secretState.approleVisible
            ? secretState.rawSecretId
            : maskSecret(secretState.rawSecretId);

        dynPwdEl.textContent = secretState.dynamicVisible
            ? secretState.rawDynamicPassword
            : maskSecret(secretState.rawDynamicPassword);

        statPwdEl.textContent = secretState.staticVisible
            ? secretState.rawStaticPassword
            : maskSecret(secretState.rawStaticPassword);
    }

    async function fetchPilotState() {
        try {
            const resp = await fetch("/api/pilot/state");
            if (!resp.ok) return;
            const data = await resp.json();

            document.getElementById("event-clock").textContent = new Date(data.timestamp).toLocaleTimeString();

            // 1. AppRole
            const approle = data.approle || {};
            document.getElementById("approle-name").textContent = approle.roleName || "spring-app-role";
            document.getElementById("approle-role-id").textContent = approle.roleId || "N/A";
            document.getElementById("approle-role-perm").textContent = approle.roleIdPermissions || "0600";
            document.getElementById("approle-secret-perm").textContent = approle.secretIdPermissions || "0600";
            secretState.rawSecretId = approle.secretId || "";
            const shortRole = (approle.roleId || "").substring(0, 13);
            document.getElementById("svg-role-id-short").textContent = `role_id: ${shortRole}...`;

            // 2. Dynamic Credential
            const dyn = (data.credentials && data.credentials.dynamic) || {};
            secretState.rawDynamicPassword = dyn.password || "";
            document.getElementById("dyn-username").textContent = dyn.username || "—";
            document.getElementById("dyn-prev-username").textContent = dyn.previousUsername || "— (inicial)";
            document.getElementById("dyn-hash").textContent = dyn.passwordHash || "--";
            document.getElementById("dyn-prev-hash").textContent = dyn.previousPasswordHash || "--";
            document.getElementById("dyn-pid").textContent = dyn.currentBackendPid ?? "--";
            document.getElementById("dyn-prev-pid").textContent = dyn.previousBackendPid ?? "--";
            document.getElementById("dyn-rot-count").textContent = dyn.rotationCount ?? 1;

            const shortDynUser = (dyn.username || "").length > 22
                ? dyn.username.substring(0, 19) + "..."
                : (dyn.username || "--");
            document.getElementById("svg-dyn-user").textContent = `user: ${shortDynUser}`;
            document.getElementById("svg-dyn-hash").textContent = `sha256: ${dyn.passwordHash || "--"}`;
            document.getElementById("svg-dyn-rot").textContent = `rotaciones: #${dyn.rotationCount || 1}`;
            document.getElementById("svg-dyn-pid").textContent = `pg_pid: ${dyn.currentBackendPid ?? "--"}`;
            document.getElementById("svg-db-dyn-role").textContent = shortDynUser;

            if (lastDynamicHash && dyn.passwordHash && dyn.passwordHash !== lastDynamicHash) {
                flashCard("card-dynamic");
                highlightNode("node-vault");
                highlightNode("node-app");
                highlightNode("node-db");
                spawnPacketBurst(paths.vaultDb, "#fbbf24", 5, 1000);
                spawnPacketBurst(paths.agentVault, "#f59e0b", 4, 900);
                spawnPacketBurst(paths.agentFiles, "#06b6d4", 4, 700);
                spawnPacketBurst(paths.appDbDyn, "#06b6d4", 5, 900);
                setBanner("ROTACIÓN DINÁMICA", `Nuevo usuario SQL efímero creado por Vault: ${dyn.username} (PID ${dyn.currentBackendPid})`);
            }
            lastDynamicHash = dyn.passwordHash;

            // 3. Static Credential
            const stat = (data.credentials && data.credentials.static) || {};
            secretState.rawStaticPassword = stat.password || "";
            document.getElementById("stat-username").textContent = stat.username || "app_static_user";
            document.getElementById("stat-hash").textContent = stat.passwordHash || "--";
            document.getElementById("stat-prev-hash").textContent = stat.previousPasswordHash || "--";
            document.getElementById("stat-pid").textContent = stat.currentBackendPid ?? "--";
            document.getElementById("stat-prev-pid").textContent = stat.previousBackendPid ?? "--";
            document.getElementById("stat-rot-count").textContent = stat.rotationCount ?? 1;

            document.getElementById("svg-stat-user").textContent = `user: ${stat.username || "app_static_user"}`;
            document.getElementById("svg-stat-hash").textContent = `sha256: ${stat.passwordHash || "--"}`;
            document.getElementById("svg-stat-rot").textContent = `rotaciones: #${stat.rotationCount || 1}`;
            document.getElementById("svg-stat-pid").textContent = `pg_pid: ${stat.currentBackendPid ?? "--"}`;

            if (lastStaticHash && stat.passwordHash && stat.passwordHash !== lastStaticHash) {
                flashCard("card-static");
                highlightNode("node-vault");
                highlightNode("node-app");
                highlightNode("node-db");
                spawnPacketBurst(paths.vaultDb, "#fbbf24", 5, 1000);
                spawnPacketBurst(paths.agentVault, "#10b981", 4, 900);
                spawnPacketBurst(paths.agentFiles, "#10b981", 4, 700);
                spawnPacketBurst(paths.appDbStat, "#10b981", 5, 900);
                setBanner("ROTACIÓN ESTÁTICA", `Password de ${stat.username} rotada en PostgreSQL (Nuevo Hash: ${stat.passwordHash}, Nuevo PID: ${stat.currentBackendPid})`);
            }
            lastStaticHash = stat.passwordHash;

            renderSecretsVisibility();

            // 4. Sesiones activas
            const sessions = data.activeSessions || [];
            const sessTbody = document.getElementById("sessions-tbody");
            sessTbody.innerHTML = sessions.map(s => {
                const isDyn = (s.username || "").startsWith("v-approle");
                const cls = isDyn ? "row-dyn" : (s.username === "app_static_user" ? "row-stat" : "");
                return `<tr class="${cls}">
                    <td><code>${s.pid}</code></td>
                    <td><code>${s.username}</code></td>
                    <td><code>${s.clientAddr}</code></td>
                    <td>${s.applicationName}</td>
                    <td>${s.state}</td>
                </tr>`;
            }).join("") || `<tr><td colspan="5">Sin sesiones</td></tr>`;

            // 5. Auditoria reciente
            const audits = data.recentAudits || [];
            if (audits.length > 0) {
                const newestId = audits[0].id;
                document.getElementById("svg-db-total-probes").textContent = `Último audit_id: #${newestId}`;
                if (lastAuditId !== null && newestId !== lastAuditId) {
                    spawnPacketBurst(paths.appDbDyn, "#06b6d4", 2, 700);
                    spawnPacketBurst(paths.appDbStat, "#10b981", 2, 700);
                }
                lastAuditId = newestId;
            }

            const auditsTbody = document.getElementById("audits-tbody");
            auditsTbody.innerHTML = audits.map(a => {
                const cls = a.credentialMode === "DYNAMIC" ? "row-dyn" : "row-stat";
                const timeStr = a.executedAt ? new Date(a.executedAt).toLocaleTimeString() : "--";
                return `<tr class="${cls}">
                    <td><code>#${a.id}</code></td>
                    <td><strong>${a.credentialMode}</strong></td>
                    <td><code>${a.dbUsername}</code></td>
                    <td><code>${a.backendPid}</code></td>
                    <td><code>${timeStr}</code></td>
                </tr>`;
            }).join("") || `<tr><td colspan="5">Sin registros</td></tr>`;
        } catch (err) {
            console.error("Error consultando /api/pilot/state:", err);
        }
    }

    async function triggerRotation(endpoint, label) {
        setBanner("EJECUTANDO", `Solicitando ${label} a HashiCorp Vault Server (172.29.0.10)...`);
        highlightNode("node-vault", 2000);
        try {
            const resp = await fetch(endpoint, { method: "POST" });
            if (resp.ok) {
                await fetchPilotState();
            }
        } catch (e) {
            setBanner("ERROR", `Fallo al solicitar rotación: ${e.message}`);
        }
    }

    function runWalkthroughAnimation() {
        const steps = [
            {
                delay: 0,
                tag: "PASO 1/5 · ANSIBLE -> VAULT",
                msg: "vm-ansible (172.29.0.40) solicita role_id y genera un secret_id nuevo en vm-vault (172.29.0.10)...",
                fn: () => {
                    highlightNode("node-ansible", 1600);
                    highlightNode("node-vault", 1600);
                    spawnPacketBurst(paths.ansibleVault, "#a855f7", 6, 1100);
                }
            },
            {
                delay: 1700,
                tag: "PASO 2/5 · ANSIBLE SSH -> VM-APP",
                msg: "Ansible se conecta por SSH (:22) a vm-app (172.29.0.30) e inyecta /etc/vault.d/role_id y secret_id (0600)...",
                fn: () => {
                    highlightNode("node-ansible", 1600);
                    highlightNode("node-app", 1600);
                    flashCard("card-approle");
                    spawnPacketBurst(paths.ansibleApp, "#c084fc", 6, 1100);
                }
            },
            {
                delay: 3400,
                tag: "PASO 3/5 · VAULT AGENT AUTO-AUTH",
                msg: "vault-agent se autentica con AppRole ante vm-vault y solicita leases para postgres-dynamic-role y postgres-static-role...",
                fn: () => {
                    highlightNode("node-app", 1600);
                    highlightNode("node-vault", 1600);
                    spawnPacketBurst(paths.agentVault, "#f59e0b", 6, 1100);
                }
            },
            {
                delay: 5100,
                tag: "PASO 4/5 · VAULT -> POSTGRESQL + RENDER",
                msg: "Vault crea rol efímero / rota password en vm-db (172.29.0.20) y vault-agent escribe /run/secrets/*.properties...",
                fn: () => {
                    highlightNode("node-vault", 1600);
                    highlightNode("node-db", 1600);
                    spawnPacketBurst(paths.vaultDb, "#fbbf24", 6, 1200);
                    spawnPacketBurst(paths.agentFiles, "#38bdf8", 6, 900);
                }
            },
            {
                delay: 6800,
                tag: "PASO 5/5 · HIKARICP HOT-RELOAD -> SQL",
                msg: "Spring Boot detecta cambio SHA-256 en /run/secrets/, recrea pools HikariCP sin reinicio e inserta en connection_audit_log.",
                fn: () => {
                    highlightNode("node-app", 1800);
                    highlightNode("node-db", 1800);
                    flashCard("card-dynamic");
                    flashCard("card-static");
                    spawnPacketBurst(paths.appDbDyn, "#06b6d4", 6, 1000);
                    spawnPacketBurst(paths.appDbStat, "#10b981", 6, 1000);
                }
            }
        ];

        steps.forEach(s => {
            setTimeout(() => {
                setBanner(s.tag, s.msg, true);
                s.fn();
            }, s.delay);
        });
    }

    document.querySelectorAll("[data-toggle-secret]").forEach(btn => {
        btn.addEventListener("click", () => {
            const type = btn.getAttribute("data-toggle-secret");
            if (type === "approle") {
                secretState.approleVisible = !secretState.approleVisible;
                btn.textContent = secretState.approleVisible ? "Ocultar" : "Mostrar";
            } else if (type === "dynamic") {
                secretState.dynamicVisible = !secretState.dynamicVisible;
                btn.textContent = secretState.dynamicVisible ? "Ocultar" : "Mostrar";
            } else if (type === "static") {
                secretState.staticVisible = !secretState.staticVisible;
                btn.textContent = secretState.staticVisible ? "Ocultar" : "Mostrar";
            }
            renderSecretsVisibility();
        });
    });

    document.getElementById("btn-rotate-dynamic").addEventListener("click", () => {
        triggerRotation("/api/pilot/rotate/dynamic", "rotación de lease dinámico");
    });

    document.getElementById("btn-rotate-static").addEventListener("click", () => {
        triggerRotation("/api/pilot/rotate/static", "rotación de password estática");
    });

    document.getElementById("btn-walkthrough").addEventListener("click", () => {
        runWalkthroughAnimation();
    });

    fetchPilotState();
    setInterval(fetchPilotState, 2000);
})();

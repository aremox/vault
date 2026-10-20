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
    let lastConfigTag = null;

    const paths = {
        ansibleVault: "M 155 170 L 155 235",
        ansibleApp: "M 280 110 L 370 110",
        agentVault: "M 280 300 L 370 230",
        agentFiles: "M 530 220 L 595 220",
        vaultDb: "M 280 345 C 540 395, 740 395, 885 320",
        appDbDyn: "M 790 155 L 885 180",
        appDbStat: "M 790 275 L 885 255",
        gitConfig: "M 280 480 L 370 480",
        vaultConfig: "M 155 375 C 155 440, 290 445, 370 455",
        configApp: "M 675 415 L 675 370"
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

            // 4. Spring Cloud Config + Gitea + Vault KV v2
            const cfg = data.springCloudConfig || {};
            if (cfg.giteaRepoUrl) {
                document.getElementById("cfg-repo-link").href = cfg.giteaRepoUrl;
            }
            document.getElementById("cfg-commit-sha").textContent = cfg.lastCommitSha || "main";
            document.getElementById("cfg-banner").textContent = cfg.banner || "—";
            document.getElementById("cfg-custom-tag").textContent = cfg.customTag || "git-v1";
            document.getElementById("cfg-environment").textContent = cfg.environment || "production-lab";
            document.getElementById("cfg-vault-kv-sig").textContent = cfg.vaultKvSignature || "—";
            document.getElementById("cfg-refresh-count").textContent = cfg.refreshCount ?? 0;
            document.getElementById("cfg-stage").textContent = cfg.vaultKvRotationStage || "STAGE-1";

            const shortKv = (cfg.vaultKvSignature || "").length > 18
                ? cfg.vaultKvSignature.substring(0, 16) + "..."
                : (cfg.vaultKvSignature || "--");
            document.getElementById("svg-cfg-tag").textContent = `tag: ${cfg.customTag || "git-v1"}`;
            document.getElementById("svg-cfg-kv").textContent = `kv: ${shortKv}`;
            document.getElementById("svg-cfg-sha").textContent = `commit: ${cfg.lastCommitSha || "main"}`;
            document.getElementById("svg-cfg-refreshes").textContent = `refreshes: #${cfg.refreshCount ?? 0}`;
            document.getElementById("svg-git-commit").textContent = `• Commit SHA: ${cfg.lastCommitSha || "main"}`;

            if (lastConfigTag && cfg.customTag && cfg.customTag !== lastConfigTag) {
                flashCard("card-spring-config");
                highlightNode("node-git", 1800);
                highlightNode("node-vault", 1800);
                highlightNode("node-config-server", 1800);
                highlightNode("node-app", 1800);
                spawnPacketBurst(paths.gitConfig, "#f43f5e", 5, 900);
                spawnPacketBurst(paths.vaultConfig, "#f59e0b", 5, 900);
                spawnPacketBurst(paths.configApp, "#fb7185", 6, 1000);
                setBanner("SPRING CLOUD REFRESH", `Commit ${cfg.lastCommitSha} en Gitea + Secreto KV en Vault recargados en caliente (@RefreshScope -> ${cfg.customTag})`);
            }
            lastConfigTag = cfg.customTag;

            renderSecretsVisibility();

            // 5. Sesiones activas
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

            // 6. Auditoria reciente
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

    async function triggerSpringCloudRefresh() {
        setBanner("SPRING CLOUD CONFIG", "Haciendo commit en Gitea (vm-git), rotando KV en Vault y ejecutando @RefreshScope vía vm-config-server...");
        highlightNode("node-git", 2000);
        highlightNode("node-vault", 2000);
        highlightNode("node-config-server", 2000);
        spawnPacketBurst(paths.gitConfig, "#f43f5e", 5, 900);
        spawnPacketBurst(paths.vaultConfig, "#f59e0b", 5, 900);
        try {
            const resp = await fetch("/api/pilot/config/refresh", { method: "POST" });
            if (resp.ok) {
                spawnPacketBurst(paths.configApp, "#fb7185", 6, 900);
                await fetchPilotState();
            }
        } catch (e) {
            setBanner("ERROR", `Fallo al refrescar Spring Cloud Config: ${e.message}`);
        }
    }

    function runWalkthroughAnimation() {
        const steps = [
            {
                delay: 0,
                tag: "PASO 1/6 · ANSIBLE -> VAULT",
                msg: "vm-ansible (172.29.0.40) solicita role_id y genera secret_id en vm-vault (172.29.0.10)...",
                fn: () => {
                    highlightNode("node-ansible", 1600);
                    highlightNode("node-vault", 1600);
                    spawnPacketBurst(paths.ansibleVault, "#a855f7", 6, 1100);
                }
            },
            {
                delay: 1600,
                tag: "PASO 2/6 · ANSIBLE SSH -> VMs",
                msg: "Ansible inyecta por SSH (:22) /etc/vault.d/role_id y secret_id (0600) en vm-config-server y vm-app...",
                fn: () => {
                    highlightNode("node-ansible", 1600);
                    highlightNode("node-config-server", 1600);
                    highlightNode("node-app", 1600);
                    flashCard("card-approle");
                    spawnPacketBurst(paths.ansibleApp, "#c084fc", 6, 1100);
                }
            },
            {
                delay: 3200,
                tag: "PASO 3/6 · GITEA + VAULT KV -> CONFIG SERVER",
                msg: "vm-config-server obtiene credenciales Git desde Vault, clona vault-rotation-pilot.yml de Gitea y combina secretos KV v2...",
                fn: () => {
                    highlightNode("node-git", 1600);
                    highlightNode("node-vault", 1600);
                    highlightNode("node-config-server", 1600);
                    flashCard("card-spring-config");
                    spawnPacketBurst(paths.gitConfig, "#f43f5e", 6, 1000);
                    spawnPacketBurst(paths.vaultConfig, "#f59e0b", 6, 1000);
                    spawnPacketBurst(paths.configApp, "#fb7185", 6, 1000);
                }
            },
            {
                delay: 4800,
                tag: "PASO 4/6 · VAULT AGENT AUTO-AUTH",
                msg: "vault-agent en vm-app se autentica con AppRole ante vm-vault y solicita leases para PostgreSQL...",
                fn: () => {
                    highlightNode("node-app", 1600);
                    highlightNode("node-vault", 1600);
                    spawnPacketBurst(paths.agentVault, "#f59e0b", 6, 1100);
                }
            },
            {
                delay: 6400,
                tag: "PASO 5/6 · VAULT -> POSTGRESQL + RENDER",
                msg: "Vault crea rol efímero / rota password en vm-db (172.29.0.20) y vault-agent escribe /run/secrets/*.properties...",
                fn: () => {
                    highlightNode("node-vault", 1600);
                    highlightNode("node-db", 1600);
                    spawnPacketBurst(paths.vaultDb, "#fbbf24", 6, 1200);
                    spawnPacketBurst(paths.agentFiles, "#38bdf8", 6, 900);
                }
            },
            {
                delay: 8000,
                tag: "PASO 6/6 · HIKARICP + @REFRESHSCOPE EN VIVO",
                msg: "Spring Boot opera sin reinicios: recarga pools HikariCP ante rotaciones SQL y beans @RefreshScope ante commits en Gitea.",
                fn: () => {
                    highlightNode("node-app", 1800);
                    highlightNode("node-db", 1800);
                    flashCard("card-dynamic");
                    flashCard("card-static");
                    flashCard("card-spring-config");
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

    document.getElementById("btn-refresh-config").addEventListener("click", () => {
        triggerSpringCloudRefresh();
    });

    document.getElementById("btn-card-refresh-config").addEventListener("click", () => {
        triggerSpringCloudRefresh();
    });

    document.getElementById("btn-walkthrough").addEventListener("click", () => {
        runWalkthroughAnimation();
    });

    fetchPilotState();
    setInterval(fetchPilotState, 2000);
})();

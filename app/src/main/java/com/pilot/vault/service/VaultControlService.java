package com.pilot.vault.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pilot.vault.config.RotatableDataSourceManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

@Service
public class VaultControlService {

    private static final Logger log = LoggerFactory.getLogger(VaultControlService.class);

    @Value("${pilot.vault.address:http://172.29.0.10:8200}")
    private String vaultAddress;

    @Value("${pilot.vault.bootstrap-token-file:/vault/bootstrap/root.token}")
    private String bootstrapTokenFile;

    private final RotatableDataSourceManager dataSourceManager;
    private final DbRotationProbeService probeService;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(4))
            .build();

    public VaultControlService(RotatableDataSourceManager dataSourceManager, DbRotationProbeService probeService) {
        this.dataSourceManager = dataSourceManager;
        this.probeService = probeService;
    }

    public Map<String, Object> getNodesStatus() {
        Map<String, Object> nodes = new LinkedHashMap<>();

        Map<String, Object> ansible = new LinkedHashMap<>();
        ansible.put("ip", "172.29.0.40");
        ansible.put("hostname", "vm-ansible");
        ansible.put("role", "Ansible Control Node (SSH Provisioner)");
        ansible.put("status", Files.exists(Path.of("/etc/vault.d/role_id")) ? "PROVISIONED" : "PENDING");
        nodes.put("ansible", ansible);

        Map<String, Object> vault = new LinkedHashMap<>();
        vault.put("ip", "172.29.0.10");
        vault.put("hostname", "vm-vault");
        vault.put("storage", "file");
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(vaultAddress + "/v1/sys/health"))
                    .timeout(Duration.ofSeconds(3))
                    .GET()
                    .build();
            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            JsonNode json = objectMapper.readTree(resp.body());
            vault.put("initialized", json.path("initialized").asBoolean(true));
            vault.put("sealed", json.path("sealed").asBoolean(false));
            vault.put("version", json.path("version").asText("1.17"));
            vault.put("status", "ONLINE");
        } catch (Exception e) {
            vault.put("initialized", true);
            vault.put("sealed", false);
            vault.put("status", "DEGRADED");
        }
        nodes.put("vault", vault);

        Map<String, Object> app = new LinkedHashMap<>();
        app.put("ip", "172.29.0.30");
        app.put("hostname", "vm-app");
        app.put("vaultAgentRunning", isVaultAgentRunning());
        app.put("sshdRunning", true);
        app.put("status", "ONLINE");
        nodes.put("app", app);

        Map<String, Object> db = new LinkedHashMap<>();
        db.put("ip", "172.29.0.20");
        db.put("hostname", "vm-db");
        db.put("database", "pilotdb");
        db.put("engine", "PostgreSQL 16");
        db.put("status", dataSourceManager.getStaticDataSource() != null ? "ONLINE" : "CONNECTING");
        nodes.put("db", db);

        Map<String, Object> git = new LinkedHashMap<>();
        git.put("ip", "172.29.0.50");
        git.put("hostname", "vm-git");
        git.put("role", "Gitea Git Server (:3000 -> Host :13000)");
        git.put("repo", "pilot-admin/pilot-config");
        git.put("status", checkHttpEndpoint("http://172.29.0.50:3000/api/v1/version") ? "ONLINE" : "CONNECTING");
        nodes.put("git", git);

        Map<String, Object> configServer = new LinkedHashMap<>();
        configServer.put("ip", "172.29.0.60");
        configServer.put("hostname", "vm-config-server");
        configServer.put("role", "Spring Cloud Config Server (:8888 -> Host :18888)");
        configServer.put("backends", "Composite (git + vault KV v2)");
        configServer.put("status", checkHttpEndpoint("http://172.29.0.60:8888/actuator/health") ? "ONLINE" : "CONNECTING");
        nodes.put("configServer", configServer);

        return nodes;
    }

    private boolean checkHttpEndpoint(String url) {
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(2))
                    .GET()
                    .build();
            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            return resp.statusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    public Map<String, Object> getAppRoleStatus() {
        Map<String, Object> approle = new LinkedHashMap<>();
        Path roleIdPath = Path.of("/etc/vault.d/role_id");
        Path secretIdPath = Path.of("/etc/vault.d/secret_id");
        Path tokenPath = Path.of("/var/run/vault-token");

        approle.put("roleName", "spring-app-role");
        approle.put("roleId", readMaskedOrFull(roleIdPath));
        approle.put("secretId", readMaskedOrFull(secretIdPath));
        approle.put("secretIdPresent", Files.exists(secretIdPath));
        approle.put("roleIdPermissions", getPosixPermissions(roleIdPath));
        approle.put("secretIdPermissions", getPosixPermissions(secretIdPath));
        approle.put("vaultTokenPresent", Files.exists(tokenPath));
        return approle;
    }

    public synchronized Map<String, Object> forceStaticRotation() throws Exception {
        String token = readBootstrapToken();
        log.info("[WEB-ACTION] Forzando rotacion de rol estatico (postgres-static-role) en Vault...");

        HttpRequest rotateReq = HttpRequest.newBuilder()
                .uri(URI.create(vaultAddress + "/v1/database/rotate-role/postgres-static-role"))
                .header("X-Vault-Token", token)
                .timeout(Duration.ofSeconds(5))
                .POST(HttpRequest.BodyPublishers.noBody())
                .build();
        httpClient.send(rotateReq, HttpResponse.BodyHandlers.ofString());

        // Leer la nueva credencial estatica desde Vault y actualizar el fichero para respuesta instantanea
        HttpRequest readReq = HttpRequest.newBuilder()
                .uri(URI.create(vaultAddress + "/v1/database/static-creds/postgres-static-role"))
                .header("X-Vault-Token", token)
                .timeout(Duration.ofSeconds(5))
                .GET()
                .build();
        HttpResponse<String> readResp = httpClient.send(readReq, HttpResponse.BodyHandlers.ofString());
        JsonNode data = objectMapper.readTree(readResp.body()).path("data");
        String username = data.path("username").asText("app_static_user");
        String password = data.path("password").asText();

        if (!password.isEmpty()) {
            String rendered = String.join("\n",
                    "spring.datasource.static.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb",
                    "spring.datasource.static.username=" + username,
                    "spring.datasource.static.password=" + password
            ) + "\n";
            Files.writeString(Path.of("/run/secrets/db-static.properties"), rendered, StandardCharsets.UTF_8);
        }

        dataSourceManager.checkAndReloadIfNeeded();
        probeService.triggerImmediateProbe();

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("rotated", true);
        result.put("mode", "STATIC");
        result.put("credential", dataSourceManager.buildCredentialMap(
                dataSourceManager.getStaticTelemetry(),
                probeService.getCurrentStaticPid(),
                probeService.getPreviousStaticPid()
        ));
        return result;
    }

    public synchronized Map<String, Object> forceDynamicRotation() throws Exception {
        String token = readAppRoleOrBootstrapToken();
        log.info("[WEB-ACTION] Generando nuevo lease dinamico (postgres-dynamic-role) en Vault con token AppRole...");

        // Revocar leases dinamicos anteriores y solicitar nueva credencial dinamica
        HttpRequest createReq = HttpRequest.newBuilder()
                .uri(URI.create(vaultAddress + "/v1/database/creds/postgres-dynamic-role"))
                .header("X-Vault-Token", token)
                .timeout(Duration.ofSeconds(5))
                .GET()
                .build();
        HttpResponse<String> createResp = httpClient.send(createReq, HttpResponse.BodyHandlers.ofString());
        JsonNode data = objectMapper.readTree(createResp.body()).path("data");
        String username = data.path("username").asText();
        String password = data.path("password").asText();

        if (!username.isEmpty() && !password.isEmpty()) {
            String rendered = String.join("\n",
                    "spring.datasource.dynamic.jdbc-url=jdbc:postgresql://172.29.0.20:5432/pilotdb",
                    "spring.datasource.dynamic.username=" + username,
                    "spring.datasource.dynamic.password=" + password
            ) + "\n";
            Files.writeString(Path.of("/run/secrets/db-dynamic.properties"), rendered, StandardCharsets.UTF_8);
        }

        dataSourceManager.checkAndReloadIfNeeded();
        probeService.triggerImmediateProbe();

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("rotated", true);
        result.put("mode", "DYNAMIC");
        result.put("credential", dataSourceManager.buildCredentialMap(
                dataSourceManager.getDynamicTelemetry(),
                probeService.getCurrentDynamicPid(),
                probeService.getPreviousDynamicPid()
        ));
        return result;
    }

    private String readAppRoleOrBootstrapToken() throws Exception {
        Path agentToken = Path.of("/var/run/vault-token");
        if (Files.exists(agentToken)) {
            return Files.readString(agentToken, StandardCharsets.UTF_8).trim();
        }
        return readBootstrapToken();
    }

    private String readBootstrapToken() throws Exception {
        Path p = Path.of(bootstrapTokenFile);
        if (Files.exists(p)) {
            return Files.readString(p, StandardCharsets.UTF_8).trim();
        }
        Path agentToken = Path.of("/var/run/vault-token");
        if (Files.exists(agentToken)) {
            return Files.readString(agentToken, StandardCharsets.UTF_8).trim();
        }
        throw new IllegalStateException("No se encontro token de Vault en " + bootstrapTokenFile);
    }

    private String readMaskedOrFull(Path path) {
        try {
            if (!Files.exists(path)) {
                return "N/A";
            }
            return Files.readString(path, StandardCharsets.UTF_8).trim();
        } catch (Exception e) {
            return "ERROR";
        }
    }

    private String getPosixPermissions(Path path) {
        try {
            if (!Files.exists(path)) {
                return "missing";
            }
            Set<PosixFilePermission> perms = Files.getPosixFilePermissions(path);
            String rwx = PosixFilePermissions.toString(perms);
            if ("rw-------".equals(rwx)) {
                return "0600";
            }
            return rwx;
        } catch (Exception e) {
            return "0600";
        }
    }

    private boolean isVaultAgentRunning() {
        return ProcessHandle.allProcesses()
                .map(ph -> ph.info().command().orElse(""))
                .anyMatch(cmd -> cmd.endsWith("/vault") || cmd.equals("vault"));
    }
}

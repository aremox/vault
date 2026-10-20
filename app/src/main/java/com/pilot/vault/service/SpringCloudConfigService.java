package com.pilot.vault.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pilot.vault.config.DynamicConfigProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.context.refresh.ContextRefresher;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class SpringCloudConfigService {

    private static final Logger log = LoggerFactory.getLogger(SpringCloudConfigService.class);

    @Value("${pilot.vault.address:http://172.29.0.10:8200}")
    private String vaultAddress;

    @Value("${pilot.vault.bootstrap-token-file:/vault/bootstrap/root.token}")
    private String bootstrapTokenFile;

    @Value("${pilot.gitea.internal-url:http://172.29.0.50:3000}")
    private String giteaInternalUrl;

    @Value("${pilot.gitea.public-url:http://localhost:13000}")
    private String giteaPublicUrl;

    @Value("${pilot.gitea.owner:pilot-admin}")
    private String giteaOwner;

    @Value("${pilot.gitea.repo:pilot-config}")
    private String giteaRepo;

    @Value("${pilot.config-server.url:http://172.29.0.60:8888}")
    private String configServerUrl;

    private final DynamicConfigProperties dynamicConfigProperties;
    private final ContextRefresher contextRefresher;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(4))
            .build();

    private final AtomicInteger manualRefreshCount = new AtomicInteger(0);
    private volatile String lastRefreshedAt = Instant.now().toString();
    private volatile String lastCommitMessage = "feat(config): initial Spring Cloud Config properties for vault-rotation-pilot";

    public SpringCloudConfigService(
            DynamicConfigProperties dynamicConfigProperties,
            ContextRefresher contextRefresher
    ) {
        this.dynamicConfigProperties = dynamicConfigProperties;
        this.contextRefresher = contextRefresher;
    }

    public Map<String, Object> getSpringCloudConfigStatus() {
        Map<String, Object> state = new LinkedHashMap<>();
        boolean giteaReachable = isGiteaReachable();
        boolean configServerReachable = isConfigServerReachable();

        state.put("configServerReachable", configServerReachable);
        state.put("giteaReachable", giteaReachable);
        state.put("giteaRepoUrl", giteaPublicUrl + "/" + giteaOwner + "/" + giteaRepo);
        state.put("configServerEndpoint", "http://localhost:18888/vault-rotation-pilot/default");
        state.put("environment", dynamicConfigProperties.getEnvironment());
        state.put("banner", dynamicConfigProperties.getBanner());
        state.put("customTag", dynamicConfigProperties.getCustomTag());
        state.put("vaultKvSignature", dynamicConfigProperties.getVaultKvSignature());
        state.put("vaultKvRotationStage", dynamicConfigProperties.getVaultKvRotationStage());
        state.put("vaultKvEncryptionSalt", dynamicConfigProperties.getVaultKvEncryptionSalt());
        state.put("lastCommitSha", fetchLatestCommitShaShort());
        state.put("lastCommitMessage", lastCommitMessage);
        state.put("refreshCount", manualRefreshCount.get());
        state.put("lastRefreshedAt", lastRefreshedAt);
        return state;
    }

    public synchronized Map<String, Object> commitInGiteaRotateKvAndRefresh() throws Exception {
        int nextSeq = Math.max(manualRefreshCount.get() + 1, dynamicConfigProperties.getRefreshCounter() + 1);
        String shortSuffix = UUID.randomUUID().toString().substring(0, 4).toUpperCase();
        String newTag = "git-v" + nextSeq + "-" + shortSuffix;
        String newBanner = "Hot-Reload #" + nextSeq + " desde Gitea (" + newTag + ") + Vault KV v2";
        String newSignature = "VAULT-KV-SIG-ROTATED-" + (9000 + nextSeq) + "-" + shortSuffix;
        String newStage = "STAGE-" + nextSeq;
        String newSalt = "SALT-LAB-" + shortSuffix;

        log.info("[SPRING-CLOUD-CONFIG] 1/3 Haciendo commit en Gitea ({}/{}) con custom-tag={}...", giteaOwner, giteaRepo, newTag);
        String commitSha = updateYamlInGitea(newBanner, newTag, nextSeq);

        log.info("[SPRING-CLOUD-CONFIG] 2/3 Rotando secreto KV v2 en Vault (secret/data/vault-rotation-pilot)...");
        updateVaultKvSecret(newSignature, newStage, newSalt);

        log.info("[SPRING-CLOUD-CONFIG] 3/3 Ejecutando ContextRefresher.refresh() (@RefreshScope)...");
        Set<String> refreshedKeys = contextRefresher.refresh();
        manualRefreshCount.set(nextSeq);
        lastRefreshedAt = Instant.now().toString();

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("refreshed", true);
        response.put("commitSha", commitSha);
        response.put("refreshedKeys", refreshedKeys);
        response.put("springCloudConfig", getSpringCloudConfigStatus());
        return response;
    }

    private String updateYamlInGitea(String newBanner, String newTag, int nextCounter) throws Exception {
        Map<String, String> gitCreds = readGitCredentialsFromVault();
        String basicAuth = Base64.getEncoder().encodeToString(
                (gitCreds.get("username") + ":" + gitCreds.get("password")).getBytes(StandardCharsets.UTF_8)
        );

        String contentsUrl = giteaInternalUrl + "/api/v1/repos/" + giteaOwner + "/" + giteaRepo + "/contents/vault-rotation-pilot.yml";
        HttpRequest getFileReq = HttpRequest.newBuilder()
                .uri(URI.create(contentsUrl))
                .header("Authorization", "Basic " + basicAuth)
                .timeout(Duration.ofSeconds(4))
                .GET()
                .build();
        HttpResponse<String> getFileResp = httpClient.send(getFileReq, HttpResponse.BodyHandlers.ofString());
        JsonNode fileJson = objectMapper.readTree(getFileResp.body());
        String currentFileSha = fileJson.path("sha").asText();

        String newYaml = String.join("\n",
                "pilot:",
                "  config:",
                "    environment: \"production-lab\"",
                "    banner: \"" + newBanner + "\"",
                "    custom-tag: \"" + newTag + "\"",
                "    refresh-counter: " + nextCounter
        ) + "\n";

        String encodedContent = Base64.getEncoder().encodeToString(newYaml.getBytes(StandardCharsets.UTF_8));
        String commitMsg = "chore(config): hot-reload #" + nextCounter + " tag=" + newTag;

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("content", encodedContent);
        payload.put("message", commitMsg);
        payload.put("sha", currentFileSha);
        payload.put("branch", "main");

        HttpRequest putFileReq = HttpRequest.newBuilder()
                .uri(URI.create(contentsUrl))
                .header("Authorization", "Basic " + basicAuth)
                .header("Content-Type", "application/json")
                .timeout(Duration.ofSeconds(5))
                .PUT(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(payload)))
                .build();
        HttpResponse<String> putFileResp = httpClient.send(putFileReq, HttpResponse.BodyHandlers.ofString());
        if (putFileResp.statusCode() >= 300) {
            throw new IllegalStateException("Gitea API devolvio HTTP " + putFileResp.statusCode() + ": " + putFileResp.body());
        }

        lastCommitMessage = commitMsg;
        JsonNode putJson = objectMapper.readTree(putFileResp.body());
        String fullSha = putJson.path("commit").path("sha").asText("");
        return fullSha.length() >= 7 ? fullSha.substring(0, 7) : fullSha;
    }

    private void updateVaultKvSecret(String signature, String stage, String salt) throws Exception {
        String token = readVaultToken();
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("pilot.vault.kv.secret-signature", signature);
        data.put("pilot.vault.kv.rotation-stage", stage);
        data.put("pilot.vault.kv.encryption-salt", salt);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("data", data);

        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(vaultAddress + "/v1/secret/data/vault-rotation-pilot"))
                .header("X-Vault-Token", token)
                .header("Content-Type", "application/json")
                .timeout(Duration.ofSeconds(5))
                .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(body)))
                .build();
        HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() >= 300) {
            throw new IllegalStateException("Vault KV v2 devolvio HTTP " + resp.statusCode() + ": " + resp.body());
        }
    }

    private Map<String, String> readGitCredentialsFromVault() {
        Map<String, String> creds = new LinkedHashMap<>();
        creds.put("username", "pilot-admin");
        creds.put("password", "gitea_secret_password_2026");
        try {
            String token = readVaultToken();
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(vaultAddress + "/v1/secret/data/git-credentials"))
                    .header("X-Vault-Token", token)
                    .timeout(Duration.ofSeconds(3))
                    .GET()
                    .build();
            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() == 200) {
                JsonNode data = objectMapper.readTree(resp.body()).path("data").path("data");
                creds.put("username", data.path("git_username").asText("pilot-admin"));
                creds.put("password", data.path("git_password").asText("gitea_secret_password_2026"));
            }
        } catch (Exception e) {
            log.debug("Usando fallback local para credenciales Gitea: {}", e.getMessage());
        }
        return creds;
    }

    private String fetchLatestCommitShaShort() {
        try {
            String url = giteaInternalUrl + "/api/v1/repos/" + giteaOwner + "/" + giteaRepo + "/commits?limit=1";
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(2))
                    .GET()
                    .build();
            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() == 200) {
                JsonNode arr = objectMapper.readTree(resp.body());
                if (arr.isArray() && !arr.isEmpty()) {
                    String sha = arr.get(0).path("sha").asText("");
                    String msg = arr.get(0).path("commit").path("message").asText("").trim();
                    if (!msg.isEmpty()) {
                        lastCommitMessage = msg;
                    }
                    return sha.length() >= 7 ? sha.substring(0, 7) : sha;
                }
            }
        } catch (Exception ignored) {
        }
        return "initial";
    }

    public boolean isGiteaReachable() {
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(giteaInternalUrl + "/api/v1/version"))
                    .timeout(Duration.ofSeconds(2))
                    .GET()
                    .build();
            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            return resp.statusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    public boolean isConfigServerReachable() {
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(configServerUrl + "/actuator/health"))
                    .timeout(Duration.ofSeconds(2))
                    .GET()
                    .build();
            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            return resp.statusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    private String readVaultToken() throws Exception {
        Path agentToken = Path.of("/var/run/vault-token");
        if (Files.exists(agentToken)) {
            return Files.readString(agentToken, StandardCharsets.UTF_8).trim();
        }
        Path bootstrap = Path.of(bootstrapTokenFile);
        if (Files.exists(bootstrap)) {
            return Files.readString(bootstrap, StandardCharsets.UTF_8).trim();
        }
        throw new IllegalStateException("No se encontro token de Vault en /var/run/vault-token ni en " + bootstrapTokenFile);
    }
}

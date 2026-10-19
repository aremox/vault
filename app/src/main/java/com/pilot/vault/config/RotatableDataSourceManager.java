package com.pilot.vault.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

@Component
public class RotatableDataSourceManager {

    private static final Logger log = LoggerFactory.getLogger(RotatableDataSourceManager.class);

    public record CredentialTelemetry(
            String mode,
            String filePath,
            String jdbcUrl,
            String username,
            String previousUsername,
            String password,
            String passwordHash,
            String previousPasswordHash,
            int rotationCount,
            String lastRotatedAt
    ) {}

    @Value("${pilot.secrets.dynamic-file:/run/secrets/db-dynamic.properties}")
    private String dynamicFilePath;

    @Value("${pilot.secrets.static-file:/run/secrets/db-static.properties}")
    private String staticFilePath;

    private final AtomicReference<HikariDataSource> dynamicPoolRef = new AtomicReference<>();
    private final AtomicReference<HikariDataSource> staticPoolRef = new AtomicReference<>();

    private final AtomicReference<CredentialTelemetry> dynamicTelemetryRef = new AtomicReference<>();
    private final AtomicReference<CredentialTelemetry> staticTelemetryRef = new AtomicReference<>();

    private final AtomicInteger dynamicRotationCount = new AtomicInteger(0);
    private final AtomicInteger staticRotationCount = new AtomicInteger(0);

    private volatile String lastDynamicHash = "";
    private volatile String lastStaticHash = "";

    private final ScheduledExecutorService closerExecutor = Executors.newSingleThreadScheduledExecutor();

    @PostConstruct
    public void init() {
        checkAndReloadIfNeeded();
    }

    public synchronized void checkAndReloadIfNeeded() {
        reloadIfChanged(
                Path.of(dynamicFilePath),
                "DYNAMIC",
                "spring.datasource.dynamic",
                lastDynamicHash,
                dynamicPoolRef,
                dynamicTelemetryRef,
                dynamicRotationCount,
                newHash -> this.lastDynamicHash = newHash
        );
        reloadIfChanged(
                Path.of(staticFilePath),
                "STATIC",
                "spring.datasource.static",
                lastStaticHash,
                staticPoolRef,
                staticTelemetryRef,
                staticRotationCount,
                newHash -> this.lastStaticHash = newHash
        );
    }

    private void reloadIfChanged(
            Path filePath,
            String mode,
            String prefix,
            String previousHash,
            AtomicReference<HikariDataSource> poolRef,
            AtomicReference<CredentialTelemetry> telemetryRef,
            AtomicInteger rotationCounter,
            java.util.function.Consumer<String> hashUpdater
    ) {
        try {
            if (!Files.exists(filePath)) {
                log.warn("[{}] Fichero de credenciales aun no existe: {}", mode, filePath);
                return;
            }
            String content = Files.readString(filePath, StandardCharsets.UTF_8).trim();
            if (content.isEmpty()) {
                return;
            }
            String currentHash = sha256(content);
            if (currentHash.equals(previousHash) && poolRef.get() != null) {
                return;
            }

            Properties props = new Properties();
            try (InputStream in = Files.newInputStream(filePath)) {
                props.load(in);
            }

            String jdbcUrl = props.getProperty(prefix + ".jdbc-url");
            String username = props.getProperty(prefix + ".username");
            String password = props.getProperty(prefix + ".password");

            if (jdbcUrl == null || username == null || password == null) {
                log.warn("[{}] Fichero {} incompleto durante renderizado, esperando siguiente ciclo.", mode, filePath);
                return;
            }

            String pwdShortHash = sha256(password).substring(0, 12);
            CredentialTelemetry prev = telemetryRef.get();
            String prevUsername = prev != null ? prev.username() : null;
            String prevPwdHash = prev != null ? prev.passwordHash() : null;
            int rotCount = rotationCounter.incrementAndGet();
            String nowIso = Instant.now().toString();

            log.info("[ROTATION-DETECTED] Modo={} | Usuario={} | HashCredencial={} | Rotacion=#{} -> Recreando pool HikariCP...",
                    mode, username, pwdShortHash, rotCount);

            HikariConfig cfg = new HikariConfig();
            cfg.setPoolName("HikariPool-" + mode + "-" + rotCount);
            cfg.setJdbcUrl(jdbcUrl);
            cfg.setUsername(username);
            cfg.setPassword(password);
            cfg.setMaximumPoolSize(2);
            cfg.setMinimumIdle(1);
            cfg.setConnectionTimeout(5000);
            cfg.setValidationTimeout(3000);

            HikariDataSource newPool = new HikariDataSource(cfg);
            HikariDataSource oldPool = poolRef.getAndSet(newPool);
            hashUpdater.accept(currentHash);

            telemetryRef.set(new CredentialTelemetry(
                    mode,
                    filePath.toString(),
                    jdbcUrl,
                    username,
                    prevUsername,
                    password,
                    pwdShortHash,
                    prevPwdHash,
                    rotCount,
                    nowIso
            ));

            if (oldPool != null) {
                closerExecutor.schedule(() -> {
                    try {
                        log.info("[POOL-EVICT] Cerrando pool HikariCP anterior para modo {}", mode);
                        oldPool.close();
                    } catch (Exception e) {
                        log.warn("Error cerrando pool anterior ({}): {}", mode, e.getMessage());
                    }
                }, 3, TimeUnit.SECONDS);
            }
        } catch (Exception e) {
            log.error("[{}] Error recargando credenciales desde {}: {}", mode, filePath, e.getMessage());
        }
    }

    public DataSource getDynamicDataSource() {
        return dynamicPoolRef.get();
    }

    public DataSource getStaticDataSource() {
        return staticPoolRef.get();
    }

    public CredentialTelemetry getDynamicTelemetry() {
        return dynamicTelemetryRef.get();
    }

    public CredentialTelemetry getStaticTelemetry() {
        return staticTelemetryRef.get();
    }

    public Map<String, Object> buildCredentialMap(CredentialTelemetry t, Integer currentPid, Integer previousPid) {
        Map<String, Object> map = new LinkedHashMap<>();
        if (t == null) {
            map.put("status", "INITIALIZING");
            return map;
        }
        map.put("mode", t.mode());
        map.put("filePath", t.filePath());
        map.put("jdbcUrl", t.jdbcUrl());
        map.put("username", t.username());
        map.put("previousUsername", t.previousUsername());
        map.put("password", t.password());
        map.put("passwordHash", t.passwordHash());
        map.put("previousPasswordHash", t.previousPasswordHash());
        map.put("currentBackendPid", currentPid);
        map.put("previousBackendPid", previousPid);
        map.put("rotationCount", t.rotationCount());
        map.put("lastRotatedAt", t.lastRotatedAt());
        return map;
    }

    private String sha256(String input) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] encoded = digest.digest(input.getBytes(StandardCharsets.UTF_8));
        return HexFormat.of().formatHex(encoded);
    }

    @PreDestroy
    public void shutdown() {
        closerExecutor.shutdownNow();
        HikariDataSource dyn = dynamicPoolRef.get();
        if (dyn != null) {
            dyn.close();
        }
        HikariDataSource stat = staticPoolRef.get();
        if (stat != null) {
            stat.close();
        }
    }
}

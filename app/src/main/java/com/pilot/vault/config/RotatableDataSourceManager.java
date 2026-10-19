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
import java.util.HexFormat;
import java.util.Properties;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@Component
public class RotatableDataSourceManager {

    private static final Logger log = LoggerFactory.getLogger(RotatableDataSourceManager.class);

    @Value("${pilot.secrets.dynamic-file:/run/secrets/db-dynamic.properties}")
    private String dynamicFilePath;

    @Value("${pilot.secrets.static-file:/run/secrets/db-static.properties}")
    private String staticFilePath;

    private final AtomicReference<HikariDataSource> dynamicPoolRef = new AtomicReference<>();
    private final AtomicReference<HikariDataSource> staticPoolRef = new AtomicReference<>();

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
                newHash -> this.lastDynamicHash = newHash
        );
        reloadIfChanged(
                Path.of(staticFilePath),
                "STATIC",
                "spring.datasource.static",
                lastStaticHash,
                staticPoolRef,
                newHash -> this.lastStaticHash = newHash
        );
    }

    private void reloadIfChanged(
            Path filePath,
            String mode,
            String prefix,
            String previousHash,
            AtomicReference<HikariDataSource> poolRef,
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

            log.info("[ROTATION-DETECTED] Modo={} | Usuario={} | HashCredencial={} -> Recreando pool HikariCP...",
                    mode, username, currentHash.substring(0, 12));

            HikariConfig cfg = new HikariConfig();
            cfg.setPoolName("HikariPool-" + mode);
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

package com.pilot.vault.service;

import com.pilot.vault.config.RotatableDataSourceManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.util.Map;

@Service
public class DbRotationProbeService {

    private static final Logger log = LoggerFactory.getLogger(DbRotationProbeService.class);

    private static final String AUDIT_SQL = """
            INSERT INTO public.connection_audit_log (credential_mode, db_username, backend_pid)
            VALUES (?, current_user, pg_backend_pid())
            RETURNING id, credential_mode, db_username, backend_pid, executed_at
            """;

    private final RotatableDataSourceManager dataSourceManager;

    public DbRotationProbeService(RotatableDataSourceManager dataSourceManager) {
        this.dataSourceManager = dataSourceManager;
    }

    @Scheduled(fixedRate = 5000)
    public void probeDatabaseConnections() {
        dataSourceManager.checkAndReloadIfNeeded();

        executeProbe("DYNAMIC", dataSourceManager.getDynamicDataSource());
        executeProbe("STATIC", dataSourceManager.getStaticDataSource());
    }

    private void executeProbe(String mode, DataSource dataSource) {
        if (dataSource == null) {
            log.warn("[PROBE-{}] DataSource aun no inicializado.", mode);
            return;
        }
        try {
            JdbcTemplate jdbcTemplate = new JdbcTemplate(dataSource);
            Map<String, Object> row = jdbcTemplate.queryForMap(AUDIT_SQL, mode);
            log.info("[PROBE-OK] modo={} | audit_id={} | db_user={} | pg_pid={} | ts={}",
                    row.get("credential_mode"),
                    row.get("id"),
                    row.get("db_username"),
                    row.get("backend_pid"),
                    row.get("executed_at"));
        } catch (Exception e) {
            log.error("[PROBE-ERROR] modo={} | fallo consulta SQL: {}", mode, e.getMessage());
        }
    }
}

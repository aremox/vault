package com.pilot.vault.service;

import com.pilot.vault.config.RotatableDataSourceManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.Timestamp;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class DbRotationProbeService {

    private static final Logger log = LoggerFactory.getLogger(DbRotationProbeService.class);

    private static final String AUDIT_SQL = """
            INSERT INTO public.connection_audit_log (credential_mode, db_username, backend_pid)
            VALUES (?, current_user, pg_backend_pid())
            RETURNING id, credential_mode, db_username, backend_pid, executed_at
            """;

    private static final String RECENT_AUDITS_SQL = """
            SELECT id, credential_mode, db_username, backend_pid, executed_at
            FROM public.connection_audit_log
            ORDER BY id DESC
            LIMIT 16
            """;

    private static final String ACTIVE_SESSIONS_SQL = """
            SELECT pid, usename, COALESCE(application_name, 'JDBC') AS application_name,
                   COALESCE(host(client_addr), 'local') AS client_addr, COALESCE(state, 'active') AS state
            FROM pg_stat_activity
            WHERE datname = 'pilotdb' AND usename IS NOT NULL AND usename <> 'postgres'
            ORDER BY pid DESC
            """;

    private final RotatableDataSourceManager dataSourceManager;

    private final AtomicReference<Integer> currentDynamicPid = new AtomicReference<>();
    private final AtomicReference<Integer> previousDynamicPid = new AtomicReference<>();
    private final AtomicReference<Integer> currentStaticPid = new AtomicReference<>();
    private final AtomicReference<Integer> previousStaticPid = new AtomicReference<>();

    public DbRotationProbeService(RotatableDataSourceManager dataSourceManager) {
        this.dataSourceManager = dataSourceManager;
    }

    @Scheduled(fixedRate = 5000)
    public void probeDatabaseConnections() {
        dataSourceManager.checkAndReloadIfNeeded();

        executeProbe("DYNAMIC", dataSourceManager.getDynamicDataSource(), currentDynamicPid, previousDynamicPid);
        executeProbe("STATIC", dataSourceManager.getStaticDataSource(), currentStaticPid, previousStaticPid);
    }

    public void triggerImmediateProbe() {
        probeDatabaseConnections();
    }

    private void executeProbe(
            String mode,
            DataSource dataSource,
            AtomicReference<Integer> currentPidRef,
            AtomicReference<Integer> prevPidRef
    ) {
        if (dataSource == null) {
            log.warn("[PROBE-{}] DataSource aun no inicializado.", mode);
            return;
        }
        try {
            JdbcTemplate jdbcTemplate = new JdbcTemplate(dataSource);
            Map<String, Object> row = jdbcTemplate.queryForMap(AUDIT_SQL, mode);
            Integer pid = ((Number) row.get("backend_pid")).intValue();
            Integer lastPid = currentPidRef.get();
            if (lastPid != null && !lastPid.equals(pid)) {
                prevPidRef.set(lastPid);
            }
            currentPidRef.set(pid);

            log.info("[PROBE-OK] modo={} | audit_id={} | db_user={} | pg_pid={} | ts={}",
                    row.get("credential_mode"),
                    row.get("id"),
                    row.get("db_username"),
                    pid,
                    row.get("executed_at"));
        } catch (Exception e) {
            log.error("[PROBE-ERROR] modo={} | fallo consulta SQL: {}", mode, e.getMessage());
        }
    }

    public List<Map<String, Object>> getRecentAudits() {
        DataSource ds = dataSourceManager.getStaticDataSource();
        if (ds == null) {
            ds = dataSourceManager.getDynamicDataSource();
        }
        if (ds == null) {
            return Collections.emptyList();
        }
        try {
            JdbcTemplate jdbc = new JdbcTemplate(ds);
            return jdbc.query(RECENT_AUDITS_SQL, (rs, rowNum) -> {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("id", rs.getLong("id"));
                item.put("credentialMode", rs.getString("credential_mode"));
                item.put("dbUsername", rs.getString("db_username"));
                item.put("backendPid", rs.getInt("backend_pid"));
                Timestamp ts = rs.getTimestamp("executed_at");
                item.put("executedAt", ts != null ? ts.toInstant().toString() : null);
                return item;
            });
        } catch (Exception e) {
            log.warn("No se pudo consultar connection_audit_log: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    public List<Map<String, Object>> getActiveSessions() {
        DataSource ds = dataSourceManager.getStaticDataSource();
        if (ds == null) {
            ds = dataSourceManager.getDynamicDataSource();
        }
        if (ds == null) {
            return Collections.emptyList();
        }
        try {
            JdbcTemplate jdbc = new JdbcTemplate(ds);
            return jdbc.query(ACTIVE_SESSIONS_SQL, (rs, rowNum) -> {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("pid", rs.getInt("pid"));
                item.put("username", rs.getString("usename"));
                item.put("applicationName", rs.getString("application_name"));
                item.put("clientAddr", rs.getString("client_addr"));
                item.put("state", rs.getString("state"));
                return item;
            });
        } catch (Exception e) {
            log.warn("No se pudo consultar pg_stat_activity: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    public Integer getCurrentDynamicPid() {
        return currentDynamicPid.get();
    }

    public Integer getPreviousDynamicPid() {
        return previousDynamicPid.get();
    }

    public Integer getCurrentStaticPid() {
        return currentStaticPid.get();
    }

    public Integer getPreviousStaticPid() {
        return previousStaticPid.get();
    }
}

package com.pilot.vault.controller;

import com.pilot.vault.config.RotatableDataSourceManager;
import com.pilot.vault.service.DbRotationProbeService;
import com.pilot.vault.service.VaultControlService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/pilot")
public class PilotDashboardController {

    private final RotatableDataSourceManager dataSourceManager;
    private final DbRotationProbeService probeService;
    private final VaultControlService vaultControlService;

    public PilotDashboardController(
            RotatableDataSourceManager dataSourceManager,
            DbRotationProbeService probeService,
            VaultControlService vaultControlService
    ) {
        this.dataSourceManager = dataSourceManager;
        this.probeService = probeService;
        this.vaultControlService = vaultControlService;
    }

    @GetMapping("/state")
    public ResponseEntity<Map<String, Object>> getPilotState() {
        dataSourceManager.checkAndReloadIfNeeded();

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("timestamp", Instant.now().toString());
        response.put("subnet", "172.29.0.0/24");
        response.put("nodes", vaultControlService.getNodesStatus());
        response.put("approle", vaultControlService.getAppRoleStatus());

        Map<String, Object> credentials = new LinkedHashMap<>();
        credentials.put("dynamic", dataSourceManager.buildCredentialMap(
                dataSourceManager.getDynamicTelemetry(),
                probeService.getCurrentDynamicPid(),
                probeService.getPreviousDynamicPid()
        ));
        credentials.put("static", dataSourceManager.buildCredentialMap(
                dataSourceManager.getStaticTelemetry(),
                probeService.getCurrentStaticPid(),
                probeService.getPreviousStaticPid()
        ));
        response.put("credentials", credentials);

        response.put("activeSessions", probeService.getActiveSessions());
        response.put("recentAudits", probeService.getRecentAudits());

        return ResponseEntity.ok(response);
    }

    @PostMapping("/rotate/static")
    public ResponseEntity<Map<String, Object>> rotateStatic() {
        try {
            return ResponseEntity.ok(vaultControlService.forceStaticRotation());
        } catch (Exception e) {
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("rotated", false);
            err.put("error", e.getMessage());
            return ResponseEntity.internalServerError().body(err);
        }
    }

    @PostMapping("/rotate/dynamic")
    public ResponseEntity<Map<String, Object>> rotateDynamic() {
        try {
            return ResponseEntity.ok(vaultControlService.forceDynamicRotation());
        } catch (Exception e) {
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("rotated", false);
            err.put("error", e.getMessage());
            return ResponseEntity.internalServerError().body(err);
        }
    }
}

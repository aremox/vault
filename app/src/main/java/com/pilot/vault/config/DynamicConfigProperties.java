package com.pilot.vault.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.stereotype.Component;

@Component
@RefreshScope
public class DynamicConfigProperties {

    @Value("${pilot.config.environment:local-fallback}")
    private String environment;

    @Value("${pilot.config.banner:Sin conexion a Spring Cloud Config}")
    private String banner;

    @Value("${pilot.config.custom-tag:git-v0}")
    private String customTag;

    @Value("${pilot.config.refresh-counter:0}")
    private int refreshCounter;

    @Value("${pilot.vault.kv.secret-signature:VAULT-KV-UNSET}")
    private String vaultKvSignature;

    @Value("${pilot.vault.kv.rotation-stage:STAGE-0}")
    private String vaultKvRotationStage;

    @Value("${pilot.vault.kv.encryption-salt:SALT-UNSET}")
    private String vaultKvEncryptionSalt;

    public String getEnvironment() {
        return environment;
    }

    public String getBanner() {
        return banner;
    }

    public String getCustomTag() {
        return customTag;
    }

    public int getRefreshCounter() {
        return refreshCounter;
    }

    public String getVaultKvSignature() {
        return vaultKvSignature;
    }

    public String getVaultKvRotationStage() {
        return vaultKvRotationStage;
    }

    public String getVaultKvEncryptionSalt() {
        return vaultKvEncryptionSalt;
    }
}

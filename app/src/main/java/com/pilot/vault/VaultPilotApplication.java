package com.pilot.vault;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class VaultPilotApplication {

    public static void main(String[] args) {
        SpringApplication.run(VaultPilotApplication.class, args);
    }
}

package com.acme.demo.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

/**
 * Main API Controller
 */
@RestController
@RequestMapping("/api")
public class ApiController {

    /**
     * Health check endpoint
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        return ResponseEntity.ok(Map.of(
            "status", "healthy",
            "timestamp", Instant.now().toString(),
            "service", "java-demo-service",
            "version", getVersion()
        ));
    }

    /**
     * Ready check for Kubernetes
     */
    @GetMapping("/ready")
    public ResponseEntity<Map<String, String>> ready() {
        return ResponseEntity.ok(Map.of(
            "status", "ready"
        ));
    }

    /**
     * Example business endpoint
     */
    @GetMapping("/info")
    public ResponseEntity<Map<String, Object>> info() {
        return ResponseEntity.ok(Map.of(
            "name", "java-demo-service",
            "description", "Java Demo Service for Golden Path",
            "stack", "Spring Boot 3.2",
            "java", System.getProperty("java.version")
        ));
    }

    private String getVersion() {
        String version = getClass().getPackage().getImplementationVersion();
        return version != null ? version : "1.0.0-SNAPSHOT";
    }
}

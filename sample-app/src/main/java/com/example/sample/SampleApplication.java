package com.example.sample;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;
import org.eclipse.microprofile.openapi.annotations.OpenAPIDefinition;
import org.eclipse.microprofile.openapi.annotations.info.Contact;
import org.eclipse.microprofile.openapi.annotations.info.Info;
import org.eclipse.microprofile.openapi.annotations.info.License;
import org.eclipse.microprofile.openapi.annotations.servers.Server;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * JAX-RS Application class.
 * Maps all REST endpoints under /api
 */
@ApplicationPath("/api")
@OpenAPIDefinition(
    info = @Info(
        title = "Sample Liberty Application API",
        version = "1.0.0",
        description = "Demo REST API for load testing and demonstrating Open Liberty capabilities. " +
                      "Provides endpoints for health checking, performance testing, and system information.",
        contact = @Contact(
            name = "Platform Team",
            url = "https://github.com/your-org/middleware-automation-platform"
        ),
        license = @License(
            name = "MIT",
            url = "https://opensource.org/licenses/MIT"
        )
    ),
    servers = {
        @Server(url = "/api", description = "Current server"),
        @Server(url = "http://localhost:9080/api", description = "Local development"),
        @Server(url = "http://192.168.68.200:9080/api", description = "Local Kubernetes (MetalLB)")
    },
    tags = {
        @Tag(name = "Greeting", description = "Simple greeting endpoints"),
        @Tag(name = "System", description = "System and server information"),
        @Tag(name = "Load Testing", description = "Endpoints for performance and load testing"),
        @Tag(name = "Statistics", description = "Application statistics and metrics")
    }
)
public class SampleApplication extends Application {
}

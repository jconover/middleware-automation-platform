package com.example.sample;

import jakarta.json.Json;
import jakarta.json.JsonArray;
import jakarta.json.JsonObject;
import jakarta.json.JsonReader;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.StringReader;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Integration tests for MicroProfile Health endpoints.
 *
 * These tests verify that the Liberty server exposes the standard
 * MicroProfile Health endpoints correctly:
 * - /health (all health checks)
 * - /health/ready (readiness probes)
 * - /health/live (liveness probes)
 * - /health/started (startup probes)
 *
 * Test naming convention: *IT.java (detected by maven-failsafe-plugin)
 */
class HealthEndpointIT {

    private static final String BASE_URL = System.getProperty("liberty.test.port") != null
            ? "http://localhost:" + System.getProperty("liberty.test.port")
            : "http://localhost:9080";

    private static final String HEALTH_BASE = BASE_URL + "/health";

    private static HttpClient httpClient;

    @BeforeAll
    static void setUp() {
        httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    /**
     * Helper method to perform GET request and return response.
     */
    private HttpResponse<String> doGet(String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(HEALTH_BASE + path))
                .GET()
                .header("Accept", "application/json")
                .timeout(Duration.ofSeconds(30))
                .build();

        return httpClient.send(request, HttpResponse.BodyHandlers.ofString());
    }

    /**
     * Helper method to parse JSON response.
     */
    private JsonObject parseJson(String json) {
        try (JsonReader reader = Json.createReader(new StringReader(json))) {
            return reader.readObject();
        }
    }

    @Nested
    @DisplayName("GET /health")
    class OverallHealthEndpointIT {

        @Test
        @DisplayName("returns 200 OK when healthy")
        void healthReturnsOkWhenHealthy() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("UP", body.getString("status"));
        }

        @Test
        @DisplayName("returns checks array")
        void healthReturnsChecksArray() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertTrue(body.containsKey("checks"));
            JsonArray checks = body.getJsonArray("checks");
            assertNotNull(checks);
        }

        @Test
        @DisplayName("returns JSON content type")
        void healthReturnsJsonContentType() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("");

            assertEquals(200, response.statusCode());
            assertTrue(response.headers().firstValue("Content-Type")
                    .orElse("")
                    .contains("application/json"));
        }
    }

    @Nested
    @DisplayName("GET /health/ready")
    class ReadinessEndpointIT {

        @Test
        @DisplayName("returns 200 OK when ready")
        void readyReturnsOkWhenReady() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/ready");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("UP", body.getString("status"));
        }

        @Test
        @DisplayName("returns checks array for readiness")
        void readyReturnsChecksArray() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/ready");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertTrue(body.containsKey("checks"));
        }
    }

    @Nested
    @DisplayName("GET /health/live")
    class LivenessEndpointIT {

        @Test
        @DisplayName("returns 200 OK when alive")
        void liveReturnsOkWhenAlive() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/live");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("UP", body.getString("status"));
        }

        @Test
        @DisplayName("returns checks array for liveness")
        void liveReturnsChecksArray() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/live");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertTrue(body.containsKey("checks"));
        }
    }

    @Nested
    @DisplayName("GET /health/started")
    class StartupEndpointIT {

        @Test
        @DisplayName("returns 200 OK when started")
        void startedReturnsOkWhenStarted() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/started");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("UP", body.getString("status"));
        }

        @Test
        @DisplayName("returns checks array for startup")
        void startedReturnsChecksArray() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/started");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertTrue(body.containsKey("checks"));
        }
    }

    @Nested
    @DisplayName("Health Response Structure")
    class HealthResponseStructureIT {

        @Test
        @DisplayName("health response contains required MicroProfile Health fields")
        void healthResponseContainsRequiredFields() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());

            // MicroProfile Health requires 'status' field
            assertTrue(body.containsKey("status"), "Response must contain 'status' field");
            String status = body.getString("status");
            assertTrue(status.equals("UP") || status.equals("DOWN"),
                    "Status must be 'UP' or 'DOWN'");

            // MicroProfile Health requires 'checks' array
            assertTrue(body.containsKey("checks"), "Response must contain 'checks' array");
        }

        @Test
        @DisplayName("individual check contains name and status")
        void individualCheckContainsNameAndStatus() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            JsonArray checks = body.getJsonArray("checks");

            // If there are any checks registered, verify their structure
            if (!checks.isEmpty()) {
                JsonObject firstCheck = checks.getJsonObject(0);
                assertTrue(firstCheck.containsKey("name"), "Check must contain 'name' field");
                assertTrue(firstCheck.containsKey("status"), "Check must contain 'status' field");
            }
        }
    }

    @Nested
    @DisplayName("Metrics Endpoint")
    class MetricsEndpointIT {

        @Test
        @DisplayName("metrics endpoint returns 200 OK")
        void metricsReturnsOk() throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(BASE_URL + "/metrics"))
                    .GET()
                    .header("Accept", "text/plain")
                    .timeout(Duration.ofSeconds(30))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            assertEquals(200, response.statusCode());
        }

        @Test
        @DisplayName("metrics endpoint returns Prometheus format")
        void metricsReturnsPrometheusFormat() throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(BASE_URL + "/metrics"))
                    .GET()
                    .header("Accept", "text/plain")
                    .timeout(Duration.ofSeconds(30))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            assertEquals(200, response.statusCode());

            // Prometheus format contains metric names with underscores and comments starting with #
            String body = response.body();
            assertTrue(body.contains("# ") || body.contains("_"),
                    "Response should be in Prometheus format");
        }

        @Test
        @DisplayName("metrics endpoint supports application/json accept header")
        void metricsSupportsJsonFormat() throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(BASE_URL + "/metrics"))
                    .GET()
                    .header("Accept", "application/json")
                    .timeout(Duration.ofSeconds(30))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            assertEquals(200, response.statusCode());
            assertTrue(response.headers().firstValue("Content-Type")
                    .orElse("")
                    .contains("application/json"));
        }
    }

    @Nested
    @DisplayName("OpenAPI Endpoint")
    class OpenAPIEndpointIT {

        @Test
        @DisplayName("openapi endpoint returns 200 OK")
        void openapiReturnsOk() throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(BASE_URL + "/openapi"))
                    .GET()
                    .header("Accept", "application/yaml")
                    .timeout(Duration.ofSeconds(30))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            assertEquals(200, response.statusCode());
        }

        @Test
        @DisplayName("openapi endpoint returns OpenAPI spec")
        void openapiReturnsSpec() throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(BASE_URL + "/openapi"))
                    .GET()
                    .header("Accept", "application/yaml")
                    .timeout(Duration.ofSeconds(30))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            assertEquals(200, response.statusCode());

            String body = response.body();
            // OpenAPI spec should contain version info
            assertTrue(body.contains("openapi:") || body.contains("\"openapi\""),
                    "Response should contain OpenAPI specification");
        }
    }
}

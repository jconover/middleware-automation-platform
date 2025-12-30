package com.example.sample;

import jakarta.ws.rs.core.Response;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for SampleResource REST endpoints.
 */
class SampleResourceTest {

    private SampleResource resource;

    @BeforeEach
    void setUp() {
        resource = new SampleResource();
    }

    @Nested
    @DisplayName("GET /api/hello")
    class HelloEndpoint {

        @Test
        @DisplayName("returns 200 OK with greeting message")
        void helloReturnsOkWithMessage() {
            Response response = resource.hello();

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Hello from Liberty!", entity.get("message"));
            assertNotNull(entity.get("timestamp"));
        }

        @Test
        @DisplayName("increments request count")
        void helloIncrementsRequestCount() {
            resource.hello();
            resource.hello();
            resource.hello();

            Response statsResponse = resource.stats();
            @SuppressWarnings("unchecked")
            Map<String, Object> stats = (Map<String, Object>) statsResponse.getEntity();

            assertEquals(3L, stats.get("totalRequests"));
        }
    }

    @Nested
    @DisplayName("GET /api/hello/{name}")
    class HelloNameEndpoint {

        @Test
        @DisplayName("returns personalized greeting")
        void helloNameReturnsPersonalizedGreeting() {
            Response response = resource.helloName("World");

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Hello, World!", entity.get("message"));
        }

        @ParameterizedTest
        @ValueSource(strings = {"Alice", "Bob", "Charlie"})
        @DisplayName("returns greeting for different names")
        void helloNameWorksWithDifferentNames(String name) {
            Response response = resource.helloName(name);

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Hello, " + name + "!", entity.get("message"));
        }
    }

    @Nested
    @DisplayName("GET /api/info")
    class InfoEndpoint {

        @Test
        @DisplayName("returns system information")
        void infoReturnsSystemInfo() {
            Response response = resource.info();

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertNotNull(entity.get("hostname"));
            assertNotNull(entity.get("javaVersion"));
            assertNotNull(entity.get("javaVendor"));
            assertNotNull(entity.get("osName"));
            assertNotNull(entity.get("osArch"));
            assertNotNull(entity.get("availableProcessors"));
            assertNotNull(entity.get("heapMemoryUsed"));
            assertNotNull(entity.get("heapMemoryMax"));
            assertNotNull(entity.get("uptime"));
            assertNotNull(entity.get("requestCount"));
            assertNotNull(entity.get("appUptime"));
        }

        @Test
        @DisplayName("returns correct processor count")
        void infoReturnsCorrectProcessorCount() {
            Response response = resource.info();

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            int actualProcessors = Runtime.getRuntime().availableProcessors();
            assertEquals(actualProcessors, entity.get("availableProcessors"));
        }
    }

    @Nested
    @DisplayName("POST /api/echo")
    class EchoEndpoint {

        @Test
        @DisplayName("echoes back the input")
        void echoReturnsInput() {
            String input = "{\"test\": \"data\"}";
            Response response = resource.echo(input);

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals(input, entity.get("echo"));
            assertEquals(input.length(), entity.get("length"));
        }

        @Test
        @DisplayName("handles empty input")
        void echoHandlesEmptyInput() {
            Response response = resource.echo("");

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("", entity.get("echo"));
            assertEquals(0, entity.get("length"));
        }
    }

    @Nested
    @DisplayName("GET /api/slow")
    class SlowEndpoint {

        @Test
        @DisplayName("caps delay at 10 seconds")
        void slowCapsDelayAt10Seconds() {
            long start = System.currentTimeMillis();
            Response response = resource.slow(15000); // Request 15 seconds
            long elapsed = System.currentTimeMillis() - start;

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            // Should be capped at 10000ms
            assertEquals(10000, entity.get("delayMs"));
            // Allow some tolerance, but should be around 10 seconds (not 15)
            assertTrue(elapsed < 12000, "Delay should be capped at ~10 seconds");
        }

        @Test
        @DisplayName("uses default delay of 1000ms")
        void slowUsesDefaultDelay() {
            long start = System.currentTimeMillis();
            Response response = resource.slow(1000);
            long elapsed = System.currentTimeMillis() - start;

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertEquals(1000, entity.get("delayMs"));
            assertTrue(elapsed >= 900, "Should delay at least 900ms");
            assertTrue(elapsed < 2000, "Should delay less than 2000ms");
        }
    }

    @Nested
    @DisplayName("GET /api/compute")
    class ComputeEndpoint {

        @Test
        @DisplayName("performs computation and returns result")
        void computeReturnsResult() {
            Response response = resource.compute(1000);

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertEquals("Computation completed", entity.get("message"));
            assertEquals(1000, entity.get("iterations"));
            assertNotNull(entity.get("result"));
            assertNotNull(entity.get("durationMs"));
        }

        @Test
        @DisplayName("caps iterations at 10 million")
        void computeCapsIterations() {
            Response response = resource.compute(20_000_000);

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertEquals(10_000_000, entity.get("iterations"));
        }
    }

    @Nested
    @DisplayName("GET /api/stats")
    class StatsEndpoint {

        @Test
        @DisplayName("returns statistics")
        void statsReturnsStatistics() {
            Response response = resource.stats();

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertNotNull(entity.get("totalRequests"));
            assertNotNull(entity.get("appUptime"));
            assertNotNull(entity.get("startTime"));
            assertNotNull(entity.get("currentTime"));
        }

        @Test
        @DisplayName("tracks request count across endpoints")
        void statsTracksRequestCount() {
            resource.hello();
            resource.helloName("Test");
            resource.info();
            resource.echo("test");

            Response response = resource.stats();
            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertEquals(4L, entity.get("totalRequests"));
        }
    }

    @Nested
    @DisplayName("POST /api/stats/reset")
    class ResetStatsEndpoint {

        @Test
        @DisplayName("resets request count to zero")
        void resetStatsResetsCount() {
            // Generate some requests
            resource.hello();
            resource.hello();
            resource.hello();

            // Reset
            Response resetResponse = resource.resetStats();
            @SuppressWarnings("unchecked")
            Map<String, Object> resetEntity = (Map<String, Object>) resetResponse.getEntity();
            assertEquals(3L, resetEntity.get("previousRequestCount"));

            // Verify reset
            Response statsResponse = resource.stats();
            @SuppressWarnings("unchecked")
            Map<String, Object> statsEntity = (Map<String, Object>) statsResponse.getEntity();
            assertEquals(0L, statsEntity.get("totalRequests"));
        }
    }
}

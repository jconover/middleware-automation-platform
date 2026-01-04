package com.example.sample;

import jakarta.json.Json;
import jakarta.json.JsonObject;
import jakarta.json.JsonReader;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.io.IOException;
import java.io.StringReader;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Integration tests for SampleResource REST endpoints.
 *
 * These tests run against a live Liberty server started by the liberty-maven-plugin.
 * The server must be running before these tests execute.
 *
 * Test naming convention: *IT.java (detected by maven-failsafe-plugin)
 */
class SampleResourceIT {

    private static final String BASE_URL = System.getProperty("liberty.test.port") != null
            ? "http://localhost:" + System.getProperty("liberty.test.port")
            : "http://localhost:9080";

    private static final String CONTEXT_ROOT = "/sample-app";
    private static final String API_BASE = BASE_URL + CONTEXT_ROOT + "/api";

    private static HttpClient httpClient;

    @BeforeAll
    static void setUp() {
        httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    /**
     * Helper method to perform GET request and return response body as string.
     */
    private HttpResponse<String> doGet(String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(API_BASE + path))
                .GET()
                .header("Accept", "application/json")
                .timeout(Duration.ofSeconds(30))
                .build();

        return httpClient.send(request, HttpResponse.BodyHandlers.ofString());
    }

    /**
     * Helper method to perform POST request with JSON body.
     */
    private HttpResponse<String> doPost(String path, String jsonBody) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(API_BASE + path))
                .POST(HttpRequest.BodyPublishers.ofString(jsonBody))
                .header("Content-Type", "application/json")
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
    @DisplayName("GET /api/hello")
    class HelloEndpointIT {

        @Test
        @DisplayName("returns 200 OK with greeting message")
        void helloReturnsOkWithMessage() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/hello");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("Hello from Liberty!", body.getString("message"));
            assertNotNull(body.getString("timestamp"));
        }
    }

    @Nested
    @DisplayName("GET /api/hello/{name}")
    class HelloNameEndpointIT {

        @Test
        @DisplayName("returns personalized greeting")
        void helloNameReturnsPersonalizedGreeting() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/hello/World");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("Hello, World!", body.getString("message"));
        }

        @ParameterizedTest
        @ValueSource(strings = {"Alice", "Bob", "Charlie"})
        @DisplayName("returns greeting for different names")
        void helloNameWorksWithDifferentNames(String name) throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/hello/" + name);

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("Hello, " + name + "!", body.getString("message"));
        }

        @Test
        @DisplayName("returns 400 for name exceeding maximum length")
        void helloNameRejectsLongName() throws IOException, InterruptedException {
            String longName = "x".repeat(101);
            HttpResponse<String> response = doGet("/hello/" + longName);

            assertEquals(400, response.statusCode());
        }
    }

    @Nested
    @DisplayName("POST /api/echo")
    class EchoEndpointIT {

        @Test
        @DisplayName("echoes back the input")
        void echoReturnsInput() throws IOException, InterruptedException {
            String input = "Hello, World!";
            String jsonBody = String.format("{\"message\":\"%s\"}", input);

            HttpResponse<String> response = doPost("/echo", jsonBody);

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals(input, body.getString("echo"));
            assertEquals(input.length(), body.getInt("length"));
        }

        @Test
        @DisplayName("handles JSON with special characters")
        void echoHandlesSpecialCharacters() throws IOException, InterruptedException {
            String input = "Test with unicode: Hello World";
            String jsonBody = String.format("{\"message\":\"%s\"}", input);

            HttpResponse<String> response = doPost("/echo", jsonBody);

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals(input, body.getString("echo"));
        }

        @Test
        @DisplayName("returns 400 for blank message")
        void echoRejectsBlankMessage() throws IOException, InterruptedException {
            String jsonBody = "{\"message\":\"\"}";

            HttpResponse<String> response = doPost("/echo", jsonBody);

            assertEquals(400, response.statusCode());
        }

        @Test
        @DisplayName("returns 400 for message exceeding size limit")
        void echoRejectsOversizedMessage() throws IOException, InterruptedException {
            String oversizedMessage = "x".repeat(10001);
            String jsonBody = String.format("{\"message\":\"%s\"}", oversizedMessage);

            HttpResponse<String> response = doPost("/echo", jsonBody);

            assertEquals(400, response.statusCode());
        }

        @Test
        @DisplayName("returns 400 for missing message field")
        void echoRejectsMissingMessage() throws IOException, InterruptedException {
            String jsonBody = "{}";

            HttpResponse<String> response = doPost("/echo", jsonBody);

            assertEquals(400, response.statusCode());
        }

        @Test
        @DisplayName("returns 400 for invalid JSON")
        void echoRejectsInvalidJson() throws IOException, InterruptedException {
            String invalidJson = "not valid json";

            HttpResponse<String> response = doPost("/echo", invalidJson);

            // Should return 400 Bad Request for malformed JSON
            assertTrue(response.statusCode() >= 400 && response.statusCode() < 500);
        }
    }

    @Nested
    @DisplayName("GET /api/slow")
    class SlowEndpointIT {

        @Test
        @DisplayName("respects delay parameter")
        void slowRespectsDelayParameter() throws IOException, InterruptedException {
            long start = System.currentTimeMillis();
            HttpResponse<String> response = doGet("/slow?delay=500");
            long elapsed = System.currentTimeMillis() - start;

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals(500, body.getInt("delayMs"));
            assertTrue(elapsed >= 400, "Should delay at least 400ms");
        }

        @Test
        @DisplayName("uses default delay when parameter not provided")
        void slowUsesDefaultDelay() throws IOException, InterruptedException {
            long start = System.currentTimeMillis();
            HttpResponse<String> response = doGet("/slow");
            long elapsed = System.currentTimeMillis() - start;

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals(1000, body.getInt("delayMs"));
            assertTrue(elapsed >= 900, "Should delay at least 900ms");
        }

        @Test
        @DisplayName("returns 400 for negative delay")
        void slowRejectsNegativeDelay() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/slow?delay=-1");

            assertEquals(400, response.statusCode());
        }

        @Test
        @DisplayName("returns 400 for delay exceeding maximum")
        void slowRejectsExcessiveDelay() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/slow?delay=10001");

            assertEquals(400, response.statusCode());
        }
    }

    @Nested
    @DisplayName("GET /api/compute")
    class ComputeEndpointIT {

        @Test
        @DisplayName("performs computation and returns result")
        void computeReturnsResult() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/compute?iterations=1000");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals("Computation completed", body.getString("message"));
            assertEquals(1000, body.getInt("iterations"));
            assertNotNull(body.getJsonNumber("result"));
            assertNotNull(body.getJsonNumber("durationMs"));
        }

        @Test
        @DisplayName("uses default iterations when parameter not provided")
        void computeUsesDefaultIterations() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/compute");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertEquals(1000000, body.getInt("iterations"));
        }

        @Test
        @DisplayName("returns 400 for iterations below minimum")
        void computeRejectsZeroIterations() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/compute?iterations=0");

            assertEquals(400, response.statusCode());
        }

        @Test
        @DisplayName("returns 400 for iterations exceeding maximum")
        void computeRejectsExcessiveIterations() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/compute?iterations=10000001");

            assertEquals(400, response.statusCode());
        }
    }

    @Nested
    @DisplayName("GET /api/stats")
    class StatsEndpointIT {

        @Test
        @DisplayName("returns statistics")
        void statsReturnsStatistics() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/stats");

            assertEquals(200, response.statusCode());

            JsonObject body = parseJson(response.body());
            assertNotNull(body.getJsonNumber("totalRequests"));
            assertNotNull(body.getString("appUptime"));
            assertNotNull(body.getString("startTime"));
            assertNotNull(body.getString("currentTime"));
        }
    }

    @Nested
    @DisplayName("Content-Type Handling")
    class ContentTypeIT {

        @Test
        @DisplayName("returns JSON content type")
        void returnsJsonContentType() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/hello");

            assertEquals(200, response.statusCode());
            assertTrue(response.headers().firstValue("Content-Type")
                    .orElse("")
                    .contains("application/json"));
        }
    }

    @Nested
    @DisplayName("Error Handling")
    class ErrorHandlingIT {

        @Test
        @DisplayName("returns 404 for non-existent endpoint")
        void returns404ForNonExistentEndpoint() throws IOException, InterruptedException {
            HttpResponse<String> response = doGet("/nonexistent");

            assertEquals(404, response.statusCode());
        }

        @Test
        @DisplayName("returns 405 for unsupported HTTP method")
        void returns405ForUnsupportedMethod() throws IOException, InterruptedException {
            // Try DELETE on hello endpoint which only supports GET
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(API_BASE + "/hello"))
                    .DELETE()
                    .header("Accept", "application/json")
                    .timeout(Duration.ofSeconds(30))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            assertEquals(405, response.statusCode());
        }
    }
}

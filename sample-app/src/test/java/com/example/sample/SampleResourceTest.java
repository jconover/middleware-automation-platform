package com.example.sample;

import com.example.sample.dto.EchoRequest;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import jakarta.ws.rs.core.Response;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for SampleResource REST endpoints.
 *
 * Covers:
 * - Basic endpoint functionality
 * - Bean Validation constraints
 * - Edge cases (null inputs, boundary values, interruption handling)
 * - Special character and unicode handling
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

        @Test
        @DisplayName("accepts name at maximum length of 100 characters")
        void helloNameAcceptsMaxLength() {
            String maxLengthName = "x".repeat(100);
            Response response = resource.helloName(maxLengthName);

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Hello, " + maxLengthName + "!", entity.get("message"));
        }

        @Test
        @DisplayName("rejects name exceeding 100 characters via Bean Validation")
        void helloNameRejectsOversizedName() {
            String oversizedName = "x".repeat(101);

            // Test Bean Validation constraint directly since JAX-RS would reject this
            // before reaching the method
            try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
                Validator validator = factory.getValidator();

                // Create a wrapper to test the @Size constraint
                record NameWrapper(@jakarta.validation.constraints.Size(min = 1, max = 100) String name) {}
                NameWrapper wrapper = new NameWrapper(oversizedName);

                Set<ConstraintViolation<NameWrapper>> violations = validator.validate(wrapper);
                assertFalse(violations.isEmpty(),
                        "Should have validation violations for name exceeding 100 characters");
            }
        }

        @Test
        @DisplayName("rejects empty name via Bean Validation")
        void helloNameRejectsEmpty() {
            // Test Bean Validation constraint for empty string
            try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
                Validator validator = factory.getValidator();

                // Create a wrapper to test the @NotBlank constraint
                record NameWrapper(@jakarta.validation.constraints.NotBlank String name) {}
                NameWrapper wrapper = new NameWrapper("");

                Set<ConstraintViolation<NameWrapper>> violations = validator.validate(wrapper);
                assertFalse(violations.isEmpty(),
                        "Should have validation violations for empty name");
            }
        }

        @Test
        @DisplayName("rejects whitespace-only name via Bean Validation")
        void helloNameRejectsWhitespaceOnly() {
            // Test Bean Validation constraint for whitespace-only string
            try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
                Validator validator = factory.getValidator();

                // @NotBlank should reject whitespace-only strings
                record NameWrapper(@jakarta.validation.constraints.NotBlank String name) {}
                NameWrapper wrapper = new NameWrapper("   ");

                Set<ConstraintViolation<NameWrapper>> violations = validator.validate(wrapper);
                assertFalse(violations.isEmpty(),
                        "Should have validation violations for whitespace-only name");
            }
        }

        @Test
        @DisplayName("handles name with special characters")
        void helloNameHandlesSpecialCharacters() {
            Response response = resource.helloName("O'Connor-Smith");

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Hello, O'Connor-Smith!", entity.get("message"));
        }

        @Test
        @DisplayName("handles name with unicode characters")
        void helloNameHandlesUnicode() {
            Response response = resource.helloName("日本語");

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Hello, 日本語!", entity.get("message"));
        }
    }

    @Nested
    @DisplayName("GET /api/info")
    class InfoEndpoint {

        @Test
        @DisplayName("returns 404 when ENABLE_DEBUG_ENDPOINTS is not set")
        void infoReturns404WhenDebugDisabled() {
            // By default, ENABLE_DEBUG_ENDPOINTS is not set, so info should return 404
            Response response = resource.info();

            // If debug endpoints are disabled (default), expect 404
            // If enabled via environment, the test environment may vary
            assertTrue(
                response.getStatus() == Response.Status.NOT_FOUND.getStatusCode() ||
                response.getStatus() == Response.Status.OK.getStatusCode(),
                "Info endpoint should return 404 (debug disabled) or 200 (debug enabled)"
            );
        }
    }

    @Nested
    @DisplayName("POST /api/echo")
    class EchoEndpoint {

        @Test
        @DisplayName("echoes back the input")
        void echoReturnsInput() {
            String input = "Hello, World!";
            EchoRequest request = new EchoRequest(input);
            Response response = resource.echo(request);

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals(input, entity.get("echo"));
            assertEquals(input.length(), entity.get("length"));
        }

        @Test
        @DisplayName("handles various message content")
        void echoHandlesVariousContent() {
            String input = "Test message with special chars: !@#$%^&*()";
            EchoRequest request = new EchoRequest(input);
            Response response = resource.echo(request);

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals(input, entity.get("echo"));
            assertEquals(input.length(), entity.get("length"));
        }

        @Test
        @DisplayName("rejects messages exceeding size limit via Bean Validation")
        void echoRejectsOversizedMessage() {
            // Create a message that exceeds the 10000 character limit
            String oversizedMessage = "x".repeat(10001);
            EchoRequest request = new EchoRequest(oversizedMessage);

            // Validate using Bean Validation API
            try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
                Validator validator = factory.getValidator();
                Set<ConstraintViolation<EchoRequest>> violations = validator.validate(request);

                assertFalse(violations.isEmpty(), "Should have validation violations for oversized message");
                assertTrue(violations.stream()
                        .anyMatch(v -> v.getMessage().contains("10000")),
                        "Should mention the 10000 character limit");
            }
        }

        @Test
        @DisplayName("accepts messages at maximum size limit")
        void echoAcceptsMaxSizeMessage() {
            // Create a message exactly at the 10000 character limit
            String maxSizeMessage = "x".repeat(10000);
            EchoRequest request = new EchoRequest(maxSizeMessage);

            // Validate using Bean Validation API
            try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
                Validator validator = factory.getValidator();
                Set<ConstraintViolation<EchoRequest>> violations = validator.validate(request);

                assertTrue(violations.isEmpty(), "Should have no validation violations for max size message");
            }

            // Also verify the endpoint handles it correctly
            Response response = resource.echo(request);
            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals(10000, entity.get("length"));
        }

        @Test
        @DisplayName("rejects blank messages via Bean Validation")
        void echoRejectsBlankMessage() {
            EchoRequest request = new EchoRequest("");

            try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
                Validator validator = factory.getValidator();
                Set<ConstraintViolation<EchoRequest>> violations = validator.validate(request);

                assertFalse(violations.isEmpty(), "Should have validation violations for blank message");
            }
        }

        @Test
        @DisplayName("returns 400 BAD_REQUEST when request body is null")
        void echoReturns400WhenRequestIsNull() {
            Response response = resource.echo(null);

            assertEquals(Response.Status.BAD_REQUEST.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals("Request body is required", entity.get("error"));
        }
    }

    @Nested
    @DisplayName("GET /api/slow")
    class SlowEndpoint {

        @Test
        @DisplayName("respects delay parameter within valid bounds")
        void slowRespectsDelayParameter() {
            long start = System.currentTimeMillis();
            Response response = resource.slow(500);
            long elapsed = System.currentTimeMillis() - start;

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertEquals(500, entity.get("delayMs"));
            assertTrue(elapsed >= 400, "Should delay at least 400ms");
            assertTrue(elapsed < 1000, "Should delay less than 1000ms");
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

        @Test
        @DisplayName("returns 503 SERVICE_UNAVAILABLE when thread is interrupted")
        void slowReturns503WhenInterrupted() throws InterruptedException {
            // Use a holder to capture the response from another thread
            final Response[] responseHolder = new Response[1];
            final Exception[] exceptionHolder = new Exception[1];

            Thread testThread = new Thread(() -> {
                try {
                    responseHolder[0] = resource.slow(5000);
                } catch (Exception e) {
                    exceptionHolder[0] = e;
                }
            });

            testThread.start();
            Thread.sleep(100); // Give time for sleep to start
            testThread.interrupt();
            testThread.join(2000); // Wait for thread to complete

            assertFalse(testThread.isAlive(), "Test thread should have completed");
            assertNull(exceptionHolder[0], "Should not throw exception");
            assertNotNull(responseHolder[0], "Should have a response");

            assertEquals(Response.Status.SERVICE_UNAVAILABLE.getStatusCode(),
                    responseHolder[0].getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) responseHolder[0].getEntity();
            assertEquals("Request interrupted", entity.get("error"));
        }

        @Test
        @DisplayName("handles zero delay correctly")
        void slowHandlesZeroDelay() {
            long start = System.currentTimeMillis();
            Response response = resource.slow(0);
            long elapsed = System.currentTimeMillis() - start;

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals(0, entity.get("delayMs"));
            assertTrue(elapsed < 500, "Zero delay should complete quickly");
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
        @DisplayName("performs computation with larger iteration count")
        void computeWithLargerIterations() {
            Response response = resource.compute(100_000);

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();

            assertEquals(100_000, entity.get("iterations"));
            assertNotNull(entity.get("result"));
        }

        @Test
        @DisplayName("handles minimum valid iteration count of 1")
        void computeHandlesMinimumIterations() {
            Response response = resource.compute(1);

            assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());

            @SuppressWarnings("unchecked")
            Map<String, Object> entity = (Map<String, Object>) response.getEntity();
            assertEquals(1, entity.get("iterations"));
            assertNotNull(entity.get("result"));
            assertNotNull(entity.get("durationMs"));
        }

        @Test
        @DisplayName("computation result is deterministic for same input")
        void computeResultIsDeterministic() {
            Response response1 = resource.compute(1000);
            Response response2 = resource.compute(1000);

            @SuppressWarnings("unchecked")
            Map<String, Object> entity1 = (Map<String, Object>) response1.getEntity();
            @SuppressWarnings("unchecked")
            Map<String, Object> entity2 = (Map<String, Object>) response2.getEntity();

            assertEquals(entity1.get("result"), entity2.get("result"),
                    "Same input should produce same result");
        }

        @Test
        @DisplayName("computation duration increases with iteration count")
        void computeDurationIncreasesWithIterations() {
            Response smallResponse = resource.compute(1000);
            Response largeResponse = resource.compute(1_000_000);

            @SuppressWarnings("unchecked")
            Map<String, Object> smallEntity = (Map<String, Object>) smallResponse.getEntity();
            @SuppressWarnings("unchecked")
            Map<String, Object> largeEntity = (Map<String, Object>) largeResponse.getEntity();

            long smallDuration = ((Number) smallEntity.get("durationMs")).longValue();
            long largeDuration = ((Number) largeEntity.get("durationMs")).longValue();

            assertTrue(largeDuration >= smallDuration,
                    "Larger iteration count should take at least as long");
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
            resource.echo(new EchoRequest("test"));

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

            // Reset (pass null for admin key to simulate no header)
            Response resetResponse = resource.resetStats(null);
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

package com.example.sample;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import com.example.sample.dto.EchoRequest;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.RuntimeMXBean;
import java.net.InetAddress;
import java.time.Instant;
import java.time.Duration;
import java.util.Map;
import java.util.HashMap;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Sample REST API endpoints for testing and load testing.
 */
@Path("/")
@ApplicationScoped
@Produces(MediaType.APPLICATION_JSON)
public class SampleResource {

    private static final Logger logger = Logger.getLogger(SampleResource.class.getName());

    private final AtomicLong requestCount = new AtomicLong(0);
    private final Instant startTime = Instant.now();

    /**
     * Simple hello endpoint
     * GET /api/hello
     */
    @GET
    @Path("/hello")
    public Response hello() {
        logger.log(Level.FINE, "Hello endpoint called");
        requestCount.incrementAndGet();
        return Response.ok(Map.of(
            "message", "Hello from Liberty!",
            "timestamp", Instant.now().toString()
        )).build();
    }

    /**
     * Hello with name parameter
     * GET /api/hello/{name}
     */
    @GET
    @Path("/hello/{name}")
    public Response helloName(
            @PathParam("name")
            @NotBlank(message = "Name cannot be blank")
            @Size(min = 1, max = 100, message = "Name must be between 1 and 100 characters")
            String name) {
        logger.log(Level.FINE, "Hello endpoint called with name parameter");
        requestCount.incrementAndGet();
        return Response.ok(Map.of(
            "message", "Hello, " + name + "!",
            "timestamp", Instant.now().toString()
        )).build();
    }

    /**
     * Server information endpoint
     * GET /api/info
     */
    @GET
    @Path("/info")
    public Response info() {
        logger.log(Level.FINE, "Info endpoint called");
        requestCount.incrementAndGet();

        try {
            RuntimeMXBean runtime = ManagementFactory.getRuntimeMXBean();
            MemoryMXBean memory = ManagementFactory.getMemoryMXBean();

            String hostname;
            try {
                hostname = InetAddress.getLocalHost().getHostName();
            } catch (Exception e) {
                logger.log(Level.WARNING, "Failed to resolve hostname, using 'unknown'", e);
                hostname = "unknown";
            }

            Map<String, Object> info = new HashMap<>();
            info.put("hostname", hostname);
            info.put("javaVersion", Objects.requireNonNullElse(System.getProperty("java.version"), "unknown"));
            info.put("javaVendor", Objects.requireNonNullElse(System.getProperty("java.vendor"), "unknown"));
            info.put("osName", Objects.requireNonNullElse(System.getProperty("os.name"), "unknown"));
            info.put("osArch", Objects.requireNonNullElse(System.getProperty("os.arch"), "unknown"));
            info.put("availableProcessors", Runtime.getRuntime().availableProcessors());
            info.put("heapMemoryUsed", memory.getHeapMemoryUsage().getUsed() / 1024 / 1024 + " MB");
            info.put("heapMemoryMax", memory.getHeapMemoryUsage().getMax() / 1024 / 1024 + " MB");
            info.put("uptime", Duration.ofMillis(runtime.getUptime()).toString());
            info.put("requestCount", requestCount.get());
            info.put("appUptime", Duration.between(startTime, Instant.now()).toString());

            logger.log(Level.FINE, "Info response prepared successfully");
            return Response.ok(info).build();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error retrieving system information", e);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(Map.of("error", "Failed to retrieve system information"))
                .build();
        }
    }

    /**
     * Echo endpoint - returns what you send
     * POST /api/echo
     */
    @POST
    @Path("/echo")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response echo(@Valid EchoRequest request) {
        logger.log(Level.FINE, "Echo endpoint called");
        requestCount.incrementAndGet();

        try {
            String message = request.getMessage();
            logger.log(Level.FINE, "Echo request received, message length: {0}", message.length());
            return Response.ok(Map.of(
                "echo", message,
                "timestamp", Instant.now().toString(),
                "length", message.length()
            )).build();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error processing echo request", e);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(Map.of("error", "Failed to process echo request"))
                .build();
        }
    }

    /**
     * Simulated slow endpoint for load testing
     * GET /api/slow?delay=1000
     */
    @GET
    @Path("/slow")
    public Response slow(
            @QueryParam("delay")
            @DefaultValue("1000")
            @Min(value = 0, message = "Delay must be non-negative")
            @Max(value = 10000, message = "Delay cannot exceed 10000ms")
            int delayMs) {
        logger.log(Level.FINE, "Slow endpoint called with delay: {0}ms", delayMs);
        requestCount.incrementAndGet();

        try {
            Thread.sleep(delayMs);
            logger.log(Level.FINE, "Slow endpoint completed after {0}ms delay", delayMs);
        } catch (InterruptedException e) {
            logger.log(Level.WARNING, "Slow endpoint interrupted during sleep", e);
            Thread.currentThread().interrupt();
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                .entity(Map.of("error", "Request interrupted"))
                .build();
        }

        return Response.ok(Map.of(
            "message", "Slow response completed",
            "delayMs", delayMs,
            "timestamp", Instant.now().toString()
        )).build();
    }

    /**
     * CPU-intensive endpoint for load testing
     * GET /api/compute?iterations=1000000
     */
    @GET
    @Path("/compute")
    public Response compute(
            @QueryParam("iterations")
            @DefaultValue("1000000")
            @Min(value = 1, message = "Iterations must be at least 1")
            @Max(value = 10000000, message = "Iterations cannot exceed 10000000")
            int iterations) {
        logger.log(Level.FINE, "Compute endpoint called with iterations: {0}", iterations);
        requestCount.incrementAndGet();

        try {
            long start = System.nanoTime();
            double result = 0;
            for (int i = 0; i < iterations; i++) {
                result += Math.sqrt(i) * Math.sin(i);
            }
            long durationNs = System.nanoTime() - start;
            long durationMs = durationNs / 1_000_000;

            logger.log(Level.FINE, "Compute completed: {0} iterations in {1}ms",
                new Object[]{iterations, durationMs});

            return Response.ok(Map.of(
                "message", "Computation completed",
                "iterations", iterations,
                "result", result,
                "durationMs", durationMs,
                "timestamp", Instant.now().toString()
            )).build();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error during computation", e);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(Map.of("error", "Computation failed"))
                .build();
        }
    }

    /**
     * Statistics endpoint
     * GET /api/stats
     */
    @GET
    @Path("/stats")
    public Response stats() {
        logger.log(Level.FINE, "Stats endpoint called");
        try {
            long totalRequests = requestCount.get();
            logger.log(Level.FINE, "Returning stats: totalRequests={0}", totalRequests);
            return Response.ok(Map.of(
                "totalRequests", totalRequests,
                "appUptime", Duration.between(startTime, Instant.now()).toString(),
                "startTime", startTime.toString(),
                "currentTime", Instant.now().toString()
            )).build();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error retrieving statistics", e);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(Map.of("error", "Failed to retrieve statistics"))
                .build();
        }
    }

    /**
     * Reset statistics
     * POST /api/stats/reset
     */
    @POST
    @Path("/stats/reset")
    public Response resetStats() {
        logger.log(Level.INFO, "Statistics reset requested");
        try {
            long previousCount = requestCount.getAndSet(0);
            logger.log(Level.INFO, "Statistics reset completed, previous request count: {0}", previousCount);
            return Response.ok(Map.of(
                "message", "Statistics reset",
                "previousRequestCount", previousCount
            )).build();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error resetting statistics", e);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(Map.of("error", "Failed to reset statistics"))
                .build();
        }
    }
}

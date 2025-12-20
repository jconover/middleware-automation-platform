package com.example.sample;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.RuntimeMXBean;
import java.net.InetAddress;
import java.time.Instant;
import java.time.Duration;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Sample REST API endpoints for testing and load testing.
 */
@Path("/")
@ApplicationScoped
@Produces(MediaType.APPLICATION_JSON)
public class SampleResource {

    private final AtomicLong requestCount = new AtomicLong(0);
    private final Instant startTime = Instant.now();

    /**
     * Simple hello endpoint
     * GET /api/hello
     */
    @GET
    @Path("/hello")
    public Response hello() {
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
    public Response helloName(@PathParam("name") String name) {
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
        requestCount.incrementAndGet();

        RuntimeMXBean runtime = ManagementFactory.getRuntimeMXBean();
        MemoryMXBean memory = ManagementFactory.getMemoryMXBean();

        String hostname;
        try {
            hostname = InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            hostname = "unknown";
        }

        Map<String, Object> info = new HashMap<>();
        info.put("hostname", hostname);
        info.put("javaVersion", System.getProperty("java.version"));
        info.put("javaVendor", System.getProperty("java.vendor"));
        info.put("osName", System.getProperty("os.name"));
        info.put("osArch", System.getProperty("os.arch"));
        info.put("availableProcessors", Runtime.getRuntime().availableProcessors());
        info.put("heapMemoryUsed", memory.getHeapMemoryUsage().getUsed() / 1024 / 1024 + " MB");
        info.put("heapMemoryMax", memory.getHeapMemoryUsage().getMax() / 1024 / 1024 + " MB");
        info.put("uptime", Duration.ofMillis(runtime.getUptime()).toString());
        info.put("requestCount", requestCount.get());
        info.put("appUptime", Duration.between(startTime, Instant.now()).toString());

        return Response.ok(info).build();
    }

    /**
     * Echo endpoint - returns what you send
     * POST /api/echo
     */
    @POST
    @Path("/echo")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response echo(String body) {
        requestCount.incrementAndGet();
        return Response.ok(Map.of(
            "echo", body,
            "timestamp", Instant.now().toString(),
            "length", body.length()
        )).build();
    }

    /**
     * Simulated slow endpoint for load testing
     * GET /api/slow?delay=1000
     */
    @GET
    @Path("/slow")
    public Response slow(@QueryParam("delay") @DefaultValue("1000") int delayMs) {
        requestCount.incrementAndGet();

        // Cap delay at 10 seconds
        int actualDelay = Math.min(delayMs, 10000);

        try {
            Thread.sleep(actualDelay);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        return Response.ok(Map.of(
            "message", "Slow response completed",
            "delayMs", actualDelay,
            "timestamp", Instant.now().toString()
        )).build();
    }

    /**
     * CPU-intensive endpoint for load testing
     * GET /api/compute?iterations=1000000
     */
    @GET
    @Path("/compute")
    public Response compute(@QueryParam("iterations") @DefaultValue("1000000") int iterations) {
        requestCount.incrementAndGet();

        // Cap iterations
        int actualIterations = Math.min(iterations, 10000000);

        long start = System.nanoTime();
        double result = 0;
        for (int i = 0; i < actualIterations; i++) {
            result += Math.sqrt(i) * Math.sin(i);
        }
        long durationNs = System.nanoTime() - start;

        return Response.ok(Map.of(
            "message", "Computation completed",
            "iterations", actualIterations,
            "result", result,
            "durationMs", durationNs / 1_000_000,
            "timestamp", Instant.now().toString()
        )).build();
    }

    /**
     * Statistics endpoint
     * GET /api/stats
     */
    @GET
    @Path("/stats")
    public Response stats() {
        return Response.ok(Map.of(
            "totalRequests", requestCount.get(),
            "appUptime", Duration.between(startTime, Instant.now()).toString(),
            "startTime", startTime.toString(),
            "currentTime", Instant.now().toString()
        )).build();
    }

    /**
     * Reset statistics
     * POST /api/stats/reset
     */
    @POST
    @Path("/stats/reset")
    public Response resetStats() {
        long previousCount = requestCount.getAndSet(0);
        return Response.ok(Map.of(
            "message", "Statistics reset",
            "previousRequestCount", previousCount
        )).build();
    }
}

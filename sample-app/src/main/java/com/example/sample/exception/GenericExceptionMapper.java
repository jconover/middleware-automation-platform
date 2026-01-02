package com.example.sample.exception;

import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import java.time.Instant;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Generic exception mapper for handling uncaught exceptions in the JAX-RS application.
 * Logs the full exception for debugging while returning a safe response to clients
 * that does not expose internal details or stack traces.
 */
@Provider
public class GenericExceptionMapper implements ExceptionMapper<Exception> {

    private static final Logger LOGGER = Logger.getLogger(GenericExceptionMapper.class.getName());

    @Override
    public Response toResponse(Exception exception) {
        // Log the full exception with stack trace for debugging/operations
        LOGGER.log(Level.SEVERE, "Unhandled exception occurred", exception);

        // Return a generic error response without exposing internal details
        return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(Map.of(
                        "error", "Internal Server Error",
                        "message", "An unexpected error occurred. Please try again later.",
                        "timestamp", Instant.now().toString()
                ))
                .type(MediaType.APPLICATION_JSON)
                .build();
    }
}

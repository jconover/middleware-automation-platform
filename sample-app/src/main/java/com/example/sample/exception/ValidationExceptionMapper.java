package com.example.sample.exception;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Maps Bean Validation constraint violations to HTTP 400 Bad Request responses.
 */
@Provider
public class ValidationExceptionMapper implements ExceptionMapper<ConstraintViolationException> {

    @Override
    public Response toResponse(ConstraintViolationException exception) {
        List<Map<String, String>> errors = exception.getConstraintViolations()
                .stream()
                .map(this::toErrorMap)
                .collect(Collectors.toList());

        return Response.status(Response.Status.BAD_REQUEST)
                .entity(Map.of(
                        "error", "Validation failed",
                        "violations", errors
                ))
                .type(MediaType.APPLICATION_JSON)
                .build();
    }

    private Map<String, String> toErrorMap(ConstraintViolation<?> violation) {
        String path = violation.getPropertyPath().toString();
        // Extract just the parameter name from paths like "helloName.name"
        if (path.contains(".")) {
            path = path.substring(path.lastIndexOf('.') + 1);
        }
        return Map.of(
                "field", path,
                "message", violation.getMessage()
        );
    }
}

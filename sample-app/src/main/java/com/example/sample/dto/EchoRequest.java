package com.example.sample.dto;

import org.eclipse.microprofile.openapi.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request DTO for the echo endpoint with Bean Validation.
 */
@Schema(description = "Request payload for the echo endpoint")
public record EchoRequest(
        @Schema(description = "The message to echo back", example = "Hello, World!", required = true)
        @NotBlank(message = "Message cannot be blank")
        @Size(min = 1, max = 10000, message = "Message must be between 1 and 10000 characters")
        String message
) {
}

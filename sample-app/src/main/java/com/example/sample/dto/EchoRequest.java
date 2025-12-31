package com.example.sample.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request DTO for the echo endpoint with Bean Validation.
 */
public class EchoRequest {

    @NotBlank(message = "Message cannot be blank")
    @Size(min = 1, max = 10000, message = "Message must be between 1 and 10000 characters")
    private String message;

    // Default constructor for JSON deserialization
    public EchoRequest() {
    }

    public EchoRequest(String message) {
        this.message = message;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}

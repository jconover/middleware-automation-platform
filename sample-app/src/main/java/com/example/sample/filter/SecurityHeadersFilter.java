package com.example.sample.filter;

import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;

/**
 * JAX-RS filter that adds security headers to all API responses.
 *
 * Security headers added:
 * - X-Content-Type-Options: nosniff - Prevents MIME type sniffing
 * - X-Frame-Options: DENY - Prevents clickjacking attacks
 * - Cache-Control: no-store - Prevents caching of sensitive data
 * - X-XSS-Protection: 1; mode=block - Enables XSS filtering in older browsers
 */
@Provider
public class SecurityHeadersFilter implements ContainerResponseFilter {

    @Override
    public void filter(ContainerRequestContext request,
                       ContainerResponseContext response) {
        // Prevent MIME type sniffing
        response.getHeaders().add("X-Content-Type-Options", "nosniff");

        // Prevent clickjacking by disallowing framing
        response.getHeaders().add("X-Frame-Options", "DENY");

        // Prevent caching of potentially sensitive API responses
        response.getHeaders().add("Cache-Control", "no-store");

        // Enable XSS protection in older browsers
        response.getHeaders().add("X-XSS-Protection", "1; mode=block");
    }
}

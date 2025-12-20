package com.example.sample;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

/**
 * JAX-RS Application class.
 * Maps all REST endpoints under /api
 */
@ApplicationPath("/api")
public class SampleApplication extends Application {
}

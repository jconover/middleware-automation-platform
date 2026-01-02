# Sample Liberty Application

A Jakarta EE 10 REST API application designed for load testing and demonstrating Open Liberty capabilities. This application serves as the workload for the Middleware Automation Platform, providing various endpoints to test server performance, resource utilization, and deployment pipelines.

## Purpose

- **Load Testing**: Endpoints for simulating CPU-intensive operations and configurable delays
- **Deployment Validation**: Health and info endpoints to verify successful deployments
- **Metrics Collection**: Request counting and statistics for monitoring integration
- **Platform Demonstration**: Showcases Jakarta EE 10 and MicroProfile 6.0 features on Open Liberty

## Technology Stack

- Java 17
- Jakarta EE 10 Web Profile
- MicroProfile 6.0
- JAX-RS for REST endpoints
- Bean Validation (Jakarta Validation)

## API Endpoints

All endpoints are served under the `/api` base path.

### GET /api/hello

Returns a simple greeting message.

**Response:**
```json
{
  "message": "Hello from Liberty!",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Example:**
```bash
curl http://localhost:9080/api/hello
```

### GET /api/hello/{name}

Returns a personalized greeting.

| Parameter | Type | Location | Constraints | Description |
|-----------|------|----------|-------------|-------------|
| name | string | path | 1-100 chars, not blank | Name to greet |

**Response:**
```json
{
  "message": "Hello, Alice!",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Example:**
```bash
curl http://localhost:9080/api/hello/Alice
```

### GET /api/info

Returns server and JVM information.

**Response:**
```json
{
  "hostname": "liberty-server-01",
  "javaVersion": "17.0.8",
  "javaVendor": "Eclipse Adoptium",
  "osName": "Linux",
  "osArch": "amd64",
  "availableProcessors": 4,
  "heapMemoryUsed": "128 MB",
  "heapMemoryMax": "512 MB",
  "uptime": "PT2H30M",
  "requestCount": 1523,
  "appUptime": "PT2H25M"
}
```

**Example:**
```bash
curl http://localhost:9080/api/info
```

### POST /api/echo

Echoes back the provided message. Useful for testing request/response handling.

| Parameter | Type | Location | Constraints | Description |
|-----------|------|----------|-------------|-------------|
| message | string | body (JSON) | 1-10,000 chars, not blank | Message to echo |

**Request Body:**
```json
{
  "message": "Hello, World!"
}
```

**Response:**
```json
{
  "echo": "Hello, World!",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "length": 13
}
```

**Example:**
```bash
curl -X POST http://localhost:9080/api/echo \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, World!"}'
```

### GET /api/slow

Simulates a slow response with configurable delay. Useful for testing timeouts and connection handling.

| Parameter | Type | Location | Constraints | Default | Description |
|-----------|------|----------|-------------|---------|-------------|
| delay | int | query | 0-10,000 ms | 1000 | Delay in milliseconds |

**Response:**
```json
{
  "message": "Slow response completed",
  "delayMs": 2000,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Examples:**
```bash
# Default 1 second delay
curl http://localhost:9080/api/slow

# Custom 2 second delay
curl "http://localhost:9080/api/slow?delay=2000"

# Minimum delay (immediate response)
curl "http://localhost:9080/api/slow?delay=0"
```

### GET /api/compute

Performs CPU-intensive calculations. Useful for load testing and autoscaling validation.

| Parameter | Type | Location | Constraints | Default | Description |
|-----------|------|----------|-------------|---------|-------------|
| iterations | int | query | 1-10,000,000 | 1,000,000 | Number of iterations |

**Response:**
```json
{
  "message": "Computation completed",
  "iterations": 1000000,
  "result": 12345.6789,
  "durationMs": 150,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Examples:**
```bash
# Default 1 million iterations
curl http://localhost:9080/api/compute

# Light computation
curl "http://localhost:9080/api/compute?iterations=10000"

# Heavy computation (for stress testing)
curl "http://localhost:9080/api/compute?iterations=10000000"
```

### GET /api/stats

Returns application statistics including total request count and uptime.

**Response:**
```json
{
  "totalRequests": 1523,
  "appUptime": "PT2H25M",
  "startTime": "2024-01-15T08:05:00.000Z",
  "currentTime": "2024-01-15T10:30:00.000Z"
}
```

**Example:**
```bash
curl http://localhost:9080/api/stats
```

### POST /api/stats/reset

Resets the request counter to zero.

**Response:**
```json
{
  "message": "Statistics reset",
  "previousRequestCount": 1523
}
```

**Example:**
```bash
curl -X POST http://localhost:9080/api/stats/reset
```

## Bean Validation Constraints

The application enforces the following validation rules:

| Endpoint | Parameter | Constraints |
|----------|-----------|-------------|
| GET /api/hello/{name} | name | Not blank, 1-100 characters |
| POST /api/echo | message | Not blank, 1-10,000 characters |
| GET /api/slow | delay | 0-10,000 milliseconds |
| GET /api/compute | iterations | 1-10,000,000 |

Validation errors return HTTP 400 Bad Request with details about the constraint violation.

## Building

### Prerequisites

- Java 17 or later
- Maven 3.8 or later

### Build the WAR File

```bash
cd sample-app
mvn clean package
```

The WAR file is generated at `target/sample-app.war`.

### Build with Tests

```bash
mvn clean verify
```

### Skip Tests

```bash
mvn clean package -DskipTests
```

## Running Locally

### Option 1: Using the Container (Recommended)

From the project root directory:

```bash
# Build the container (multi-stage build compiles the app)
podman build -t liberty-app:1.0.0 -f containers/liberty/Containerfile .

# Run the container
podman run -d -p 9080:9080 -p 9443:9443 --name liberty liberty-app:1.0.0

# Verify
curl http://localhost:9080/api/hello
```

### Option 2: Using Liberty Dev Mode

If you have Open Liberty installed locally with the Liberty Maven plugin:

```bash
cd sample-app
mvn liberty:dev
```

This starts Liberty in development mode with hot reload enabled.

### Option 3: Deploy to Existing Liberty Server

1. Build the WAR: `mvn clean package`
2. Copy `target/sample-app.war` to your Liberty server's `dropins/` directory
3. Ensure your `server.xml` includes the required features:
   - `jakartaee-10.0` or individual features (restfulWS-3.1, jsonb-3.0, cdi-4.0, beanValidation-3.0)

## Testing

### Run Unit Tests

```bash
mvn test
```

### Run Tests with Code Coverage Report

```bash
mvn verify
```

### Run Static Analysis

```bash
# PMD static analysis
mvn pmd:pmd

# Checkstyle
mvn checkstyle:checkstyle
```

### Test Structure

Tests are located in `src/test/java/com/example/sample/`:

- `SampleResourceTest.java` - Unit tests for all REST endpoints
  - Tests for response status codes and content
  - Bean Validation constraint tests
  - Request counting and statistics tests
  - Parameterized tests for various inputs

### Manual Testing

After starting the application, test the endpoints:

```bash
# Health check (if Liberty health feature enabled)
curl http://localhost:9080/health/ready

# Test all endpoints
curl http://localhost:9080/api/hello
curl http://localhost:9080/api/hello/Developer
curl http://localhost:9080/api/info
curl -X POST http://localhost:9080/api/echo -H "Content-Type: application/json" -d '{"message":"test"}'
curl http://localhost:9080/api/slow?delay=500
curl http://localhost:9080/api/compute?iterations=100000
curl http://localhost:9080/api/stats
```

## Project Structure

```
sample-app/
├── pom.xml                           # Maven build configuration
├── README.md                         # This file
└── src/
    ├── main/
    │   └── java/
    │       └── com/example/sample/
    │           ├── SampleApplication.java   # JAX-RS application config
    │           ├── SampleResource.java      # REST endpoint implementations
    │           └── dto/
    │               └── EchoRequest.java     # Request DTO with validation
    └── test/
        └── java/
            └── com/example/sample/
                └── SampleResourceTest.java  # Unit tests
```

## Integration with the Platform

This application is deployed by the Middleware Automation Platform through:

- **CI/CD Pipeline**: Jenkins builds the WAR, creates a container image, and deploys to ECS or EC2
- **Container Image**: Built using the multi-stage Containerfile at `containers/liberty/Containerfile`
- **Monitoring**: Exposes metrics via MicroProfile Metrics at `/metrics` (when deployed on Liberty)
- **Health Checks**: Liberty provides `/health/ready`, `/health/live`, and `/health/started` endpoints

## Related Documentation

- [Main Project README](../README.md)
- [Local Kubernetes Deployment](../docs/LOCAL_KUBERNETES_DEPLOYMENT.md)
- [Local Podman Deployment](../docs/LOCAL_PODMAN_DEPLOYMENT.md)
- [End-to-End Testing Guide](../docs/END_TO_END_TESTING.md)

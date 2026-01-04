# Database Migrations Guide

This document describes how to work with database migrations in the Middleware Automation Platform using Flyway.

## Overview

The platform uses [Flyway](https://flywaydb.org/) for database schema versioning and migrations. Flyway tracks which migrations have been applied to each database and ensures consistent schema across all environments.

**Key Benefits:**
- Version-controlled database schema changes
- Automated migration execution in CI/CD pipeline
- Consistent schema across dev, staging, and production
- Rollback documentation for each migration
- Audit trail of all schema changes

## Quick Start

### Local Development

```bash
# Start a local PostgreSQL database
docker run -d --name postgres-dev \
  -e POSTGRES_USER=developer \
  -e POSTGRES_PASSWORD=devpass \
  -e POSTGRES_DB=middleware_dev \
  -p 5432:5432 \
  postgres:15

# Run migrations
cd sample-app
mvn flyway:migrate \
  -Dflyway.url=jdbc:postgresql://localhost:5432/middleware_dev \
  -Dflyway.user=developer \
  -Dflyway.password=devpass

# Check migration status
mvn flyway:info \
  -Dflyway.url=jdbc:postgresql://localhost:5432/middleware_dev \
  -Dflyway.user=developer \
  -Dflyway.password=devpass
```

### Using Environment Variables

```bash
# Set environment variables
export FLYWAY_URL=jdbc:postgresql://localhost:5432/middleware_dev
export FLYWAY_USER=developer
export FLYWAY_PASSWORD=devpass

# Run commands without inline credentials
cd sample-app
mvn flyway:info
mvn flyway:validate
mvn flyway:migrate
```

## Migration Files

### Location

Migration files are stored in:
```
sample-app/src/main/resources/db/migration/
```

### Naming Convention

Flyway uses a strict naming convention for migration files:

```
V{version}__{description}.sql     # Versioned migrations (applied once)
R__{description}.sql              # Repeatable migrations (applied when changed)
```

**Version Format:**
- Simple integers: `V1`, `V2`, `V3`
- Semantic versioning: `V1_0_0`, `V1_0_1`, `V2_0_0`
- Timestamp-based: `V20260104120000` (for large teams)

**Examples:**
```
V1__create_schema.sql
V2__add_audit_tables.sql
V3__add_user_preferences.sql
V4__add_indexes_for_performance.sql
R__views_and_functions.sql
```

**Rules:**
- Version numbers must be unique
- Use double underscore `__` between version and description
- Use underscores `_` in descriptions (no spaces)
- Keep descriptions concise but meaningful
- Never modify an applied migration (create a new one instead)

## Creating New Migrations

### Step 1: Create the Migration File

```bash
# Create a new migration file
touch sample-app/src/main/resources/db/migration/V3__add_feature_flags.sql
```

### Step 2: Write the Migration SQL

```sql
-- =============================================================================
-- V3__add_feature_flags.sql
-- Feature flags table for runtime configuration
-- =============================================================================
--
-- JIRA: MW-1234
-- Author: Your Name
-- Date: 2026-01-04
--
-- Rollback Instructions:
-- DROP TABLE IF EXISTS feature_flags CASCADE;
-- =============================================================================

SET search_path TO public;

CREATE TABLE IF NOT EXISTS feature_flags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    flag_name VARCHAR(100) NOT NULL UNIQUE,
    enabled BOOLEAN DEFAULT FALSE,
    percentage INTEGER DEFAULT 100 CHECK (percentage BETWEEN 0 AND 100),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_feature_flags_name ON feature_flags(flag_name);

COMMENT ON TABLE feature_flags IS 'Runtime feature flags for gradual rollouts';
```

### Step 3: Validate the Migration

```bash
# Validate all migrations (checks SQL syntax and naming)
mvn flyway:validate \
  -Dflyway.url=jdbc:postgresql://localhost:5432/middleware_dev \
  -Dflyway.user=developer \
  -Dflyway.password=devpass
```

### Step 4: Test Locally

```bash
# Apply the migration
mvn flyway:migrate \
  -Dflyway.url=jdbc:postgresql://localhost:5432/middleware_dev \
  -Dflyway.user=developer \
  -Dflyway.password=devpass

# Verify the migration was applied
mvn flyway:info \
  -Dflyway.url=jdbc:postgresql://localhost:5432/middleware_dev \
  -Dflyway.user=developer \
  -Dflyway.password=devpass
```

### Step 5: Commit and Push

```bash
git add sample-app/src/main/resources/db/migration/V3__add_feature_flags.sql
git commit -m "Add feature flags table (V3 migration)"
git push
```

## Flyway Commands

| Command | Description |
|---------|-------------|
| `mvn flyway:info` | Show migration status and history |
| `mvn flyway:validate` | Validate migrations without applying |
| `mvn flyway:migrate` | Apply pending migrations |
| `mvn flyway:repair` | Repair schema history table (use with caution) |
| `mvn flyway:clean` | Drop all objects (DISABLED in production) |
| `mvn flyway:baseline` | Baseline an existing database |

### Command Examples

```bash
# View migration status
mvn flyway:info -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...

# Dry-run validation before deployment
mvn flyway:validate -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...

# Apply migrations with verbose output
mvn flyway:migrate -X -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
```

## CI/CD Pipeline Integration

The Jenkins pipeline includes a **Database Migration** stage that:

1. Retrieves database credentials from AWS Secrets Manager (for prod-aws)
2. Validates all migration files
3. Applies pending migrations
4. Displays the current schema state

### Pipeline Flow

```
Build Application
      |
      v
 Unit Tests
      |
      v
 Code Quality
      |
      v
Build Container
      |
      v
Security Scan
      |
      v
Integration Tests
      |
      v
Database Migration  <-- Runs here, before deployment
      |
      v
Push to Registry
      |
      v
   Deploy
```

### Jenkins Credentials Setup

For non-AWS environments, configure these Jenkins credentials:

| Credential ID | Type | Description |
|---------------|------|-------------|
| `db-credentials-dev` | Username/Password | Dev database user credentials |
| `db-url-dev` | Secret text | Dev database JDBC URL |
| `db-credentials-staging` | Username/Password | Staging database user credentials |
| `db-url-staging` | Secret text | Staging database JDBC URL |

For AWS environments, credentials are automatically retrieved from Secrets Manager.

## Rollback Procedures

**Important:** Flyway does not support automatic rollbacks. Each migration should include manual rollback instructions.

### Manual Rollback Process

1. **Identify the migration to rollback:**
   ```bash
   mvn flyway:info -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
   ```

2. **Execute the rollback SQL:**
   - Find the rollback instructions in the migration file header
   - Connect to the database and execute the rollback SQL manually

   ```sql
   -- Example: Rollback V3__add_feature_flags.sql
   DROP TABLE IF EXISTS feature_flags CASCADE;
   ```

3. **Repair the schema history:**
   ```bash
   mvn flyway:repair -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
   ```

4. **Verify the rollback:**
   ```bash
   mvn flyway:info -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
   ```

### Writing Rollback-Friendly Migrations

```sql
-- =============================================================================
-- V4__add_customer_tier.sql
-- Add customer tier column to users table
-- =============================================================================
--
-- Rollback Instructions:
-- 1. ALTER TABLE users DROP COLUMN IF EXISTS customer_tier;
-- 2. DROP TYPE IF EXISTS customer_tier_enum;
-- =============================================================================

-- Create enum type
CREATE TYPE customer_tier_enum AS ENUM ('FREE', 'BASIC', 'PREMIUM', 'ENTERPRISE');

-- Add column with default value
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS customer_tier customer_tier_enum DEFAULT 'FREE';

-- Backfill existing users (make it idempotent)
UPDATE users
SET customer_tier = 'FREE'
WHERE customer_tier IS NULL;
```

## Best Practices

### DO

- **Version Control**: Always commit migration files with your application code
- **Idempotent**: Use `IF EXISTS` / `IF NOT EXISTS` where possible
- **Document**: Include rollback instructions in migration header
- **Test Locally**: Always test migrations on a local database first
- **Small Changes**: Prefer many small migrations over few large ones
- **Review**: Code review migrations like any other code change
- **Backups**: Ensure database backups before production migrations

### DON'T

- **Never** modify an applied migration
- **Never** delete migration files that have been applied
- **Never** use `flyway:clean` in production
- **Avoid** long-running DDL statements that lock tables
- **Avoid** data migrations in the same file as schema changes
- **Don't** include credentials in migration files

### Migration Patterns

**Safe Column Addition:**
```sql
-- Add column with default (no table lock in PostgreSQL 11+)
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login TIMESTAMP WITH TIME ZONE;
```

**Safe Column Removal (Two-Phase):**
```sql
-- Phase 1: Stop using the column in application code (deploy first)
-- Phase 2: Remove the column (deploy after Phase 1 is stable)
ALTER TABLE users DROP COLUMN IF EXISTS deprecated_field;
```

**Index Creation (Non-Blocking):**
```sql
-- Create index concurrently (doesn't lock the table)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email ON users(email);
```

## Troubleshooting

### Common Issues

#### Checksum Mismatch

**Error:** `Migration checksum mismatch for migration version X`

**Cause:** An applied migration file was modified.

**Solution:**
1. Never modify applied migrations
2. If necessary, use `flyway:repair` to update the checksum
   ```bash
   mvn flyway:repair -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
   ```

#### Out of Order Migration

**Error:** `Detected applied migration not resolved locally`

**Cause:** A teammate's migration was applied before yours.

**Solution:** For development, enable out-of-order:
```bash
mvn flyway:migrate -Dflyway.outOfOrder=true -Dflyway.url=...
```

#### Connection Refused

**Error:** `Connection to localhost:5432 refused`

**Cause:** Database is not running or wrong connection details.

**Solution:**
1. Verify database is running
2. Check the JDBC URL, username, and password
3. Verify network connectivity

#### Schema Validation Failed

**Error:** `Validate failed: Migrations have failed validation`

**Cause:** SQL syntax error or missing migration file.

**Solution:**
1. Check SQL syntax in migration files
2. Ensure all migration files exist
3. Run `mvn flyway:info` to see the specific issue

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
mvn flyway:migrate -X -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
```

## Environment-Specific Configuration

### Development

```properties
flyway.url=jdbc:postgresql://localhost:5432/middleware_dev
flyway.user=developer
flyway.password=devpass
flyway.outOfOrder=true
flyway.cleanDisabled=false
```

### Staging

```properties
flyway.url=jdbc:postgresql://staging-db.internal:5432/middleware
flyway.user=app_user
flyway.outOfOrder=false
flyway.cleanDisabled=true
```

### Production

```properties
flyway.url=jdbc:postgresql://prod-db.internal:5432/middleware
flyway.user=app_user
flyway.outOfOrder=false
flyway.cleanDisabled=true
flyway.baselineOnMigrate=false
```

## Security Considerations

1. **Never commit credentials** to version control
2. **Use Secrets Manager** for production credentials
3. **Limit database user permissions** to only what Flyway needs:
   - `CREATE`, `ALTER`, `DROP` on schema objects
   - `SELECT`, `INSERT`, `UPDATE`, `DELETE` on `flyway_schema_history`
4. **Audit migration changes** through code review
5. **Monitor migration execution** in CI/CD logs

## Reference

- [Flyway Documentation](https://documentation.red-gate.com/fd/)
- [Flyway Maven Plugin](https://documentation.red-gate.com/fd/maven-goal-184127408.html)
- [PostgreSQL Best Practices](https://wiki.postgresql.org/wiki/Don't_Do_This)
- [Schema Migration Patterns](https://martinfowler.com/articles/evodb.html)

## Current Migrations

| Version | Description | Applied |
|---------|-------------|---------|
| V1 | Base schema (users, roles, sessions, config) | - |
| V2 | Audit tables (events, authentication, data changes, security) | - |

## Getting Help

- **Slack**: #middleware-platform
- **Documentation**: This file and linked Flyway docs
- **Issues**: Create a JIRA ticket with the `database` label

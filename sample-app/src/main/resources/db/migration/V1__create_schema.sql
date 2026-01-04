-- =============================================================================
-- V1__create_schema.sql
-- Initial database schema for the Middleware Automation Platform sample app
-- =============================================================================
--
-- This migration creates the base schema for the Liberty sample application.
-- Tables support the REST API endpoints and application functionality.
--
-- Author: Middleware Platform Team
-- Date: 2026-01-04
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schema Settings
-- -----------------------------------------------------------------------------
SET search_path TO public;

-- -----------------------------------------------------------------------------
-- Extension Setup
-- -----------------------------------------------------------------------------
-- UUID generation for primary keys
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- Application Configuration Table
-- Stores runtime configuration that can be modified without redeployment
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    config_key VARCHAR(255) NOT NULL UNIQUE,
    config_value TEXT,
    description VARCHAR(500),
    encrypted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for fast key lookups
CREATE INDEX idx_app_config_key ON app_config(config_key);

COMMENT ON TABLE app_config IS 'Runtime application configuration settings';
COMMENT ON COLUMN app_config.config_key IS 'Unique configuration key (e.g., feature.flag.enabled)';
COMMENT ON COLUMN app_config.encrypted IS 'Whether the value is encrypted at rest';

-- -----------------------------------------------------------------------------
-- Users Table
-- Core user information for the application
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(100) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(200),
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'LOCKED', 'PENDING')),
    failed_login_attempts INTEGER DEFAULT 0,
    last_login_at TIMESTAMP WITH TIME ZONE,
    password_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for user lookups
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);

COMMENT ON TABLE users IS 'Application user accounts';
COMMENT ON COLUMN users.password_hash IS 'BCrypt hashed password - never store plaintext';
COMMENT ON COLUMN users.failed_login_attempts IS 'Counter for account lockout policy';

-- -----------------------------------------------------------------------------
-- Roles Table
-- Role-based access control (RBAC) roles
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE roles IS 'RBAC roles for authorization';

-- Insert default roles
INSERT INTO roles (name, description) VALUES
    ('ADMIN', 'Full system administrator access'),
    ('USER', 'Standard user access'),
    ('READONLY', 'Read-only access to resources'),
    ('API_CLIENT', 'Programmatic API access only');

-- -----------------------------------------------------------------------------
-- User Roles Junction Table
-- Many-to-many relationship between users and roles
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    granted_by UUID REFERENCES users(id),
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX idx_user_roles_user ON user_roles(user_id);
CREATE INDEX idx_user_roles_role ON user_roles(role_id);

COMMENT ON TABLE user_roles IS 'User to role assignments';

-- -----------------------------------------------------------------------------
-- Sessions Table
-- Active user sessions for session management
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    user_agent VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_token ON sessions(token_hash);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

COMMENT ON TABLE sessions IS 'Active user sessions for stateful authentication';
COMMENT ON COLUMN sessions.token_hash IS 'SHA-256 hash of the session token';

-- -----------------------------------------------------------------------------
-- API Keys Table
-- Long-lived API keys for programmatic access
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    key_prefix VARCHAR(10) NOT NULL,
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    scopes TEXT[] DEFAULT ARRAY['read'],
    rate_limit_per_minute INTEGER DEFAULT 60,
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_api_keys_user ON api_keys(user_id);
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);

COMMENT ON TABLE api_keys IS 'API keys for programmatic access';
COMMENT ON COLUMN api_keys.key_prefix IS 'First 8 chars of key for identification without exposing full key';
COMMENT ON COLUMN api_keys.key_hash IS 'SHA-256 hash of the full API key';

-- -----------------------------------------------------------------------------
-- Sample Data Table
-- Demonstration data table for the sample REST API
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sample_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    tags TEXT[],
    metadata JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 0,
    owner_id UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sample_data_name ON sample_data(name);
CREATE INDEX idx_sample_data_category ON sample_data(category);
CREATE INDEX idx_sample_data_tags ON sample_data USING GIN(tags);
CREATE INDEX idx_sample_data_metadata ON sample_data USING GIN(metadata);
CREATE INDEX idx_sample_data_active ON sample_data(is_active) WHERE is_active = TRUE;

COMMENT ON TABLE sample_data IS 'Sample data for REST API demonstrations';

-- -----------------------------------------------------------------------------
-- Health Check Table
-- Used by health endpoints to verify database connectivity
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health_check (
    id INTEGER PRIMARY KEY DEFAULT 1,
    last_check TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'OK',
    CONSTRAINT single_row CHECK (id = 1)
);

-- Insert the single health check row
INSERT INTO health_check (id, status) VALUES (1, 'OK');

COMMENT ON TABLE health_check IS 'Single-row table for database health verification';

-- -----------------------------------------------------------------------------
-- Database Functions
-- -----------------------------------------------------------------------------

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update trigger to relevant tables
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_app_config_updated_at
    BEFORE UPDATE ON app_config
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sample_data_updated_at
    BEFORE UPDATE ON sample_data
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------------------------
-- Initial Configuration Data
-- -----------------------------------------------------------------------------
INSERT INTO app_config (config_key, config_value, description) VALUES
    ('app.version', '1.0.0', 'Current application version'),
    ('feature.rate_limiting.enabled', 'true', 'Enable API rate limiting'),
    ('feature.rate_limiting.requests_per_minute', '60', 'Default rate limit per client'),
    ('feature.audit.enabled', 'true', 'Enable audit logging'),
    ('maintenance.mode', 'false', 'Put application in maintenance mode');

-- =============================================================================
-- Migration Complete
-- =============================================================================

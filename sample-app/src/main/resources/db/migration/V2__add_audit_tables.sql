-- =============================================================================
-- V2__add_audit_tables.sql
-- Audit logging tables for compliance and security monitoring
-- =============================================================================
--
-- This migration adds comprehensive audit logging capabilities to track:
-- - User authentication events (login, logout, password changes)
-- - Data modifications (create, update, delete operations)
-- - API access patterns
-- - Security events (failed logins, permission denials)
--
-- Supports SOC 2 compliance requirements for audit trails.
--
-- Author: Middleware Platform Team
-- Date: 2026-01-04
-- =============================================================================

SET search_path TO public;

-- -----------------------------------------------------------------------------
-- Audit Events Table
-- Core audit log for all application events
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL,
    event_category VARCHAR(30) NOT NULL,
    severity VARCHAR(10) DEFAULT 'INFO' CHECK (severity IN ('DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL')),

    -- Actor information
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(100),
    ip_address INET,
    user_agent VARCHAR(500),
    session_id UUID,

    -- Resource information
    resource_type VARCHAR(100),
    resource_id VARCHAR(255),
    resource_name VARCHAR(255),

    -- Event details
    action VARCHAR(50) NOT NULL,
    outcome VARCHAR(20) DEFAULT 'SUCCESS' CHECK (outcome IN ('SUCCESS', 'FAILURE', 'PARTIAL', 'UNKNOWN')),
    description TEXT,

    -- Change tracking
    old_values JSONB,
    new_values JSONB,

    -- Additional metadata
    request_id VARCHAR(100),
    correlation_id VARCHAR(100),
    metadata JSONB DEFAULT '{}'::jsonb,

    -- Timestamps
    event_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for efficient audit queries
CREATE INDEX idx_audit_events_time ON audit_events(event_time DESC);
CREATE INDEX idx_audit_events_user ON audit_events(user_id);
CREATE INDEX idx_audit_events_type ON audit_events(event_type);
CREATE INDEX idx_audit_events_category ON audit_events(event_category);
CREATE INDEX idx_audit_events_resource ON audit_events(resource_type, resource_id);
CREATE INDEX idx_audit_events_outcome ON audit_events(outcome);
CREATE INDEX idx_audit_events_severity ON audit_events(severity) WHERE severity IN ('WARN', 'ERROR', 'CRITICAL');
CREATE INDEX idx_audit_events_correlation ON audit_events(correlation_id) WHERE correlation_id IS NOT NULL;

-- Partial index for recent events (common query pattern)
CREATE INDEX idx_audit_events_recent ON audit_events(event_time DESC)
    WHERE event_time > CURRENT_TIMESTAMP - INTERVAL '30 days';

COMMENT ON TABLE audit_events IS 'Comprehensive audit log for security and compliance';
COMMENT ON COLUMN audit_events.event_type IS 'Specific event type (e.g., USER_LOGIN, DATA_UPDATE)';
COMMENT ON COLUMN audit_events.event_category IS 'High-level category (AUTH, DATA, SECURITY, SYSTEM)';
COMMENT ON COLUMN audit_events.correlation_id IS 'ID to correlate related events across services';
COMMENT ON COLUMN audit_events.old_values IS 'Previous state for update/delete operations';
COMMENT ON COLUMN audit_events.new_values IS 'New state for create/update operations';

-- -----------------------------------------------------------------------------
-- Authentication Audit Table
-- Specialized table for authentication events (high-volume, security-critical)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_authentication (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(30) NOT NULL CHECK (event_type IN (
        'LOGIN_SUCCESS', 'LOGIN_FAILURE', 'LOGOUT',
        'PASSWORD_CHANGE', 'PASSWORD_RESET_REQUEST', 'PASSWORD_RESET_COMPLETE',
        'MFA_ENABLED', 'MFA_DISABLED', 'MFA_CHALLENGE_SUCCESS', 'MFA_CHALLENGE_FAILURE',
        'SESSION_CREATED', 'SESSION_EXPIRED', 'SESSION_REVOKED',
        'ACCOUNT_LOCKED', 'ACCOUNT_UNLOCKED'
    )),

    -- User identification
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(100) NOT NULL,

    -- Client information
    ip_address INET NOT NULL,
    user_agent VARCHAR(500),
    geo_country VARCHAR(2),
    geo_city VARCHAR(100),

    -- Event details
    success BOOLEAN NOT NULL,
    failure_reason VARCHAR(100),

    -- Session tracking
    session_id UUID,

    -- Risk indicators
    risk_score INTEGER DEFAULT 0,
    risk_factors TEXT[],

    -- Timestamps
    event_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for authentication audit queries
CREATE INDEX idx_audit_auth_time ON audit_authentication(event_time DESC);
CREATE INDEX idx_audit_auth_user ON audit_authentication(user_id);
CREATE INDEX idx_audit_auth_username ON audit_authentication(username);
CREATE INDEX idx_audit_auth_ip ON audit_authentication(ip_address);
CREATE INDEX idx_audit_auth_type ON audit_authentication(event_type);
CREATE INDEX idx_audit_auth_failures ON audit_authentication(username, event_time DESC)
    WHERE success = FALSE;

COMMENT ON TABLE audit_authentication IS 'Authentication-specific audit events for security monitoring';
COMMENT ON COLUMN audit_authentication.risk_score IS 'Calculated risk score (0-100) based on various factors';
COMMENT ON COLUMN audit_authentication.risk_factors IS 'List of identified risk factors for this auth event';

-- -----------------------------------------------------------------------------
-- Data Change Audit Table
-- Tracks all data modifications for compliance
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_data_changes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),

    -- Table/entity information
    schema_name VARCHAR(100) DEFAULT 'public',
    table_name VARCHAR(100) NOT NULL,
    record_id VARCHAR(255) NOT NULL,

    -- Actor information
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(100),
    application_name VARCHAR(100),

    -- Change details
    old_data JSONB,
    new_data JSONB,
    changed_columns TEXT[],

    -- Context
    transaction_id BIGINT,
    statement_id INTEGER,

    -- Timestamps
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for data change audit
CREATE INDEX idx_audit_data_time ON audit_data_changes(changed_at DESC);
CREATE INDEX idx_audit_data_table ON audit_data_changes(table_name);
CREATE INDEX idx_audit_data_record ON audit_data_changes(table_name, record_id);
CREATE INDEX idx_audit_data_user ON audit_data_changes(user_id);
CREATE INDEX idx_audit_data_operation ON audit_data_changes(operation);

-- Partial index for recent changes (common query pattern)
CREATE INDEX idx_audit_data_recent ON audit_data_changes(changed_at DESC)
    WHERE changed_at > CURRENT_TIMESTAMP - INTERVAL '90 days';

COMMENT ON TABLE audit_data_changes IS 'Row-level audit trail for data modifications';
COMMENT ON COLUMN audit_data_changes.changed_columns IS 'List of columns that were modified (for UPDATE)';

-- -----------------------------------------------------------------------------
-- API Access Audit Table
-- Tracks API endpoint usage for analytics and security
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_api_access (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Request information
    method VARCHAR(10) NOT NULL,
    path VARCHAR(500) NOT NULL,
    query_string VARCHAR(2000),

    -- Client identification
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    api_key_id UUID REFERENCES api_keys(id) ON DELETE SET NULL,
    ip_address INET NOT NULL,
    user_agent VARCHAR(500),

    -- Response information
    status_code INTEGER NOT NULL,
    response_time_ms INTEGER,
    response_size_bytes INTEGER,

    -- Request context
    request_id VARCHAR(100) NOT NULL,
    correlation_id VARCHAR(100),

    -- Rate limiting
    rate_limit_remaining INTEGER,
    rate_limit_reset_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    request_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for API access audit
CREATE INDEX idx_audit_api_time ON audit_api_access(request_time DESC);
CREATE INDEX idx_audit_api_user ON audit_api_access(user_id);
CREATE INDEX idx_audit_api_path ON audit_api_access(path);
CREATE INDEX idx_audit_api_status ON audit_api_access(status_code);
CREATE INDEX idx_audit_api_ip ON audit_api_access(ip_address);
CREATE INDEX idx_audit_api_request ON audit_api_access(request_id);

-- Partial indexes for common queries
CREATE INDEX idx_audit_api_errors ON audit_api_access(request_time DESC)
    WHERE status_code >= 400;
CREATE INDEX idx_audit_api_slow ON audit_api_access(request_time DESC)
    WHERE response_time_ms > 1000;

COMMENT ON TABLE audit_api_access IS 'API request/response audit for usage analytics and security';

-- -----------------------------------------------------------------------------
-- Security Events Table
-- High-priority security events requiring attention
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_security_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'BRUTE_FORCE_DETECTED', 'CREDENTIAL_STUFFING', 'SUSPICIOUS_ACTIVITY',
        'PRIVILEGE_ESCALATION', 'UNAUTHORIZED_ACCESS', 'DATA_EXFILTRATION_ATTEMPT',
        'RATE_LIMIT_EXCEEDED', 'INVALID_TOKEN', 'IP_BLOCKED',
        'SQL_INJECTION_ATTEMPT', 'XSS_ATTEMPT', 'CSRF_ATTEMPT',
        'PERMISSION_DENIED', 'ADMIN_ACTION', 'CONFIG_CHANGE'
    )),
    severity VARCHAR(10) NOT NULL CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),

    -- Actor information
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(100),
    ip_address INET,
    user_agent VARCHAR(500),

    -- Event details
    description TEXT NOT NULL,
    details JSONB,

    -- Response actions
    action_taken VARCHAR(100),
    blocked BOOLEAN DEFAULT FALSE,

    -- Alert status
    acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_by UUID REFERENCES users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    event_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for security events
CREATE INDEX idx_audit_security_time ON audit_security_events(event_time DESC);
CREATE INDEX idx_audit_security_type ON audit_security_events(event_type);
CREATE INDEX idx_audit_security_severity ON audit_security_events(severity);
CREATE INDEX idx_audit_security_ip ON audit_security_events(ip_address);
CREATE INDEX idx_audit_security_unack ON audit_security_events(event_time DESC)
    WHERE acknowledged = FALSE;
CREATE INDEX idx_audit_security_critical ON audit_security_events(event_time DESC)
    WHERE severity IN ('HIGH', 'CRITICAL') AND acknowledged = FALSE;

COMMENT ON TABLE audit_security_events IS 'Security-specific events requiring monitoring and response';

-- -----------------------------------------------------------------------------
-- Audit Retention Policy View
-- Helper view for audit data retention management
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW audit_retention_stats AS
SELECT
    'audit_events' AS table_name,
    COUNT(*) AS total_records,
    MIN(event_time) AS oldest_record,
    MAX(event_time) AS newest_record,
    pg_size_pretty(pg_total_relation_size('audit_events')) AS table_size
FROM audit_events
UNION ALL
SELECT
    'audit_authentication',
    COUNT(*),
    MIN(event_time),
    MAX(event_time),
    pg_size_pretty(pg_total_relation_size('audit_authentication'))
FROM audit_authentication
UNION ALL
SELECT
    'audit_data_changes',
    COUNT(*),
    MIN(changed_at),
    MAX(changed_at),
    pg_size_pretty(pg_total_relation_size('audit_data_changes'))
FROM audit_data_changes
UNION ALL
SELECT
    'audit_api_access',
    COUNT(*),
    MIN(request_time),
    MAX(request_time),
    pg_size_pretty(pg_total_relation_size('audit_api_access'))
FROM audit_api_access
UNION ALL
SELECT
    'audit_security_events',
    COUNT(*),
    MIN(event_time),
    MAX(event_time),
    pg_size_pretty(pg_total_relation_size('audit_security_events'))
FROM audit_security_events;

COMMENT ON VIEW audit_retention_stats IS 'Statistics for audit table retention management';

-- -----------------------------------------------------------------------------
-- Audit Helper Functions
-- -----------------------------------------------------------------------------

-- Function to log a general audit event
CREATE OR REPLACE FUNCTION log_audit_event(
    p_event_type VARCHAR(50),
    p_event_category VARCHAR(30),
    p_action VARCHAR(50),
    p_user_id UUID DEFAULT NULL,
    p_resource_type VARCHAR(100) DEFAULT NULL,
    p_resource_id VARCHAR(255) DEFAULT NULL,
    p_outcome VARCHAR(20) DEFAULT 'SUCCESS',
    p_description TEXT DEFAULT NULL,
    p_old_values JSONB DEFAULT NULL,
    p_new_values JSONB DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
    v_audit_id UUID;
BEGIN
    INSERT INTO audit_events (
        event_type, event_category, action, user_id,
        resource_type, resource_id, outcome, description,
        old_values, new_values, metadata
    ) VALUES (
        p_event_type, p_event_category, p_action, p_user_id,
        p_resource_type, p_resource_id, p_outcome, p_description,
        p_old_values, p_new_values, p_metadata
    )
    RETURNING id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_audit_event IS 'Helper function to insert audit events';

-- Function to log authentication events
CREATE OR REPLACE FUNCTION log_auth_event(
    p_event_type VARCHAR(30),
    p_username VARCHAR(100),
    p_ip_address INET,
    p_success BOOLEAN,
    p_user_id UUID DEFAULT NULL,
    p_user_agent VARCHAR(500) DEFAULT NULL,
    p_failure_reason VARCHAR(100) DEFAULT NULL,
    p_session_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_audit_id UUID;
BEGIN
    INSERT INTO audit_authentication (
        event_type, username, ip_address, success,
        user_id, user_agent, failure_reason, session_id
    ) VALUES (
        p_event_type, p_username, p_ip_address, p_success,
        p_user_id, p_user_agent, p_failure_reason, p_session_id
    )
    RETURNING id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_auth_event IS 'Helper function to insert authentication audit events';

-- Function to purge old audit data (for retention policy)
CREATE OR REPLACE FUNCTION purge_old_audit_data(
    p_retention_days INTEGER DEFAULT 365
)
RETURNS TABLE(table_name TEXT, deleted_count BIGINT) AS $$
DECLARE
    v_cutoff_date TIMESTAMP WITH TIME ZONE;
    v_count BIGINT;
BEGIN
    v_cutoff_date := CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL;

    -- Purge audit_events
    DELETE FROM audit_events WHERE event_time < v_cutoff_date;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    table_name := 'audit_events';
    deleted_count := v_count;
    RETURN NEXT;

    -- Purge audit_authentication
    DELETE FROM audit_authentication WHERE event_time < v_cutoff_date;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    table_name := 'audit_authentication';
    deleted_count := v_count;
    RETURN NEXT;

    -- Purge audit_data_changes
    DELETE FROM audit_data_changes WHERE changed_at < v_cutoff_date;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    table_name := 'audit_data_changes';
    deleted_count := v_count;
    RETURN NEXT;

    -- Purge audit_api_access (shorter retention - 90 days default)
    DELETE FROM audit_api_access WHERE request_time < v_cutoff_date;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    table_name := 'audit_api_access';
    deleted_count := v_count;
    RETURN NEXT;

    -- Do NOT purge audit_security_events automatically
    -- These require manual review and acknowledgment

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION purge_old_audit_data IS 'Purge audit data older than specified retention period';

-- -----------------------------------------------------------------------------
-- Update app_config with audit settings
-- -----------------------------------------------------------------------------
INSERT INTO app_config (config_key, config_value, description) VALUES
    ('audit.retention.days', '365', 'Number of days to retain audit data'),
    ('audit.api_access.enabled', 'true', 'Enable API access logging'),
    ('audit.data_changes.enabled', 'true', 'Enable data change tracking'),
    ('audit.security.alert_threshold', '3', 'Number of failed attempts before security alert');

-- =============================================================================
-- Migration Complete
-- =============================================================================

# AlertManager Configuration Guide

This guide explains how to configure AlertManager webhook notifications for the middleware automation platform.

## Overview

AlertManager handles alert routing and notifications from Prometheus. This platform supports multiple notification channels:
- **Slack** - Team chat notifications
- **PagerDuty** - On-call alerting
- **Email** - Traditional email notifications
- **Custom Webhooks** - Integration with any HTTP endpoint

## Configuration File Location

| Environment | Location |
|-------------|----------|
| AWS Production | `/etc/alertmanager/alertmanager.yml` (on monitoring server) |
| Local Kubernetes | ConfigMap `alertmanager-prometheus-kube-prometheus-alertmanager` |
| Local Development | `monitoring/alertmanager/alertmanager.yml` |

## Slack Configuration

### 1. Create Slack Webhook

1. Go to [Slack API](https://api.slack.com/apps)
2. Click "Create New App" > "From scratch"
3. Name it "AlertManager" and select your workspace
4. Go to "Incoming Webhooks" > Enable
5. Click "Add New Webhook to Workspace"
6. Select the channel (e.g., `#middleware-alerts`)
7. Copy the webhook URL

### 2. Configure AlertManager

```yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  receiver: 'slack-notifications'
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    - match:
        severity: critical
      receiver: 'slack-critical'
    - match:
        severity: warning
      receiver: 'slack-warnings'

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#middleware-alerts'
        send_resolved: true
        title: '{{ .Status | toUpper }}: {{ .CommonLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *Alert:* {{ .Labels.alertname }}
          *Severity:* {{ .Labels.severity }}
          *Description:* {{ .Annotations.description }}
          {{ end }}

  - name: 'slack-critical'
    slack_configs:
      - channel: '#middleware-critical'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        title: 'CRITICAL: {{ .CommonLabels.alertname }}'

  - name: 'slack-warnings'
    slack_configs:
      - channel: '#middleware-alerts'
        send_resolved: true
        color: 'warning'
```

### Slack Security Best Practices

**Don't commit webhook URLs to git.** Use one of these approaches:

**Option 1: File-based secret**
```yaml
global:
  slack_api_url_file: '/etc/alertmanager/secrets/slack-webhook'
```

**Option 2: Environment variable (Kubernetes)**
```yaml
# In alertmanager deployment
env:
  - name: SLACK_WEBHOOK_URL
    valueFrom:
      secretKeyRef:
        name: alertmanager-secrets
        key: slack-webhook
```

## PagerDuty Configuration

### 1. Get Integration Key

1. Log in to PagerDuty
2. Go to Services > Service Directory
3. Select your service (or create new)
4. Go to Integrations tab
5. Add "Prometheus" integration
6. Copy the Integration Key

### 2. Configure AlertManager

```yaml
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'
        severity: '{{ .CommonLabels.severity }}'
        description: '{{ .CommonAnnotations.summary }}'
        details:
          alertname: '{{ .CommonLabels.alertname }}'
          cluster: '{{ .CommonLabels.cluster }}'

route:
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
```

## Email Configuration

```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alertmanager@example.com'
  smtp_auth_password: 'app-password-here'

receivers:
  - name: 'email-team'
    email_configs:
      - to: 'team@example.com'
        send_resolved: true
        headers:
          Subject: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
```

### AWS SES Configuration

```yaml
global:
  smtp_smarthost: 'email-smtp.us-east-1.amazonaws.com:587'
  smtp_from: 'alerts@yourdomain.com'
  smtp_auth_username: 'AKIAIOSFODNN7EXAMPLE'
  smtp_auth_password: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
```

## Custom Webhook Configuration

For integrating with custom systems:

```yaml
receivers:
  - name: 'custom-webhook'
    webhook_configs:
      - url: 'https://your-system.example.com/alerts'
        send_resolved: true
        http_config:
          bearer_token: 'your-api-token'
        max_alerts: 10
```

## Multi-Severity Routing

Complete example with multiple severity levels:

```yaml
route:
  receiver: 'default'
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    # Critical alerts -> PagerDuty + Slack
    - match:
        severity: critical
      receiver: 'critical-alerts'
      continue: true  # Also send to Slack

    - match:
        severity: critical
      receiver: 'slack-critical'

    # Warning alerts -> Slack only
    - match:
        severity: warning
      receiver: 'slack-warnings'

    # Info alerts -> Email digest
    - match:
        severity: info
      receiver: 'email-digest'
      group_wait: 1h
      group_interval: 6h

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#middleware-alerts'

  - name: 'critical-alerts'
    pagerduty_configs:
      - service_key_file: '/etc/alertmanager/secrets/pagerduty-key'

  - name: 'slack-critical'
    slack_configs:
      - channel: '#middleware-critical'

  - name: 'slack-warnings'
    slack_configs:
      - channel: '#middleware-alerts'

  - name: 'email-digest'
    email_configs:
      - to: 'team@example.com'
```

## Inhibition Rules

Reduce alert noise by suppressing alerts when related critical alerts are firing:

```yaml
inhibit_rules:
  # If LibertyServerDown is firing, suppress LibertyHighHeapUsage
  - source_match:
      alertname: 'LibertyServerDown'
    target_match:
      alertname: 'LibertyHighHeapUsage'
    equal: ['job', 'instance']

  # If ECSLibertyNoTasks is firing, suppress ECSLibertyTaskDown
  - source_match:
      alertname: 'ECSLibertyNoTasks'
    target_match:
      alertname: 'ECSLibertyTaskDown'
    equal: ['job']

  # Critical alerts inhibit warning alerts for same alertname
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
```

## Testing Notifications

### Method 1: amtool (Recommended)

```bash
# Install amtool (comes with AlertManager)
amtool alert add alertname=TestAlert severity=warning \
  --alertmanager.url=http://localhost:9093

# Check alert status
amtool alert query --alertmanager.url=http://localhost:9093
```

### Method 2: API

```bash
curl -X POST http://alertmanager:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "job": "liberty"
    },
    "annotations": {
      "summary": "Test alert",
      "description": "This is a test alert"
    }
  }]'
```

### Method 3: Prometheus Test Rule

Add to `monitoring/prometheus/rules/test-alerts.yml`:

```yaml
groups:
  - name: test
    rules:
      - alert: TestAlertAlwaysFiring
        expr: vector(1)
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Test alert - always fires"
```

## Troubleshooting

### Alerts Not Being Sent

1. **Check AlertManager status:**
   ```bash
   curl http://alertmanager:9093/api/v1/status
   ```

2. **Check active alerts:**
   ```bash
   curl http://alertmanager:9093/api/v1/alerts
   ```

3. **Check AlertManager logs:**
   ```bash
   # AWS
   journalctl -u alertmanager -f

   # Kubernetes
   kubectl logs -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0
   ```

### Slack 403 Forbidden

- Webhook URL expired or revoked
- Regenerate webhook in Slack app settings

### Configuration Syntax Errors

```bash
# Validate configuration
amtool check-config alertmanager.yml

# Or use promtool
promtool check config alertmanager.yml
```

### Reload Configuration

```bash
# Send SIGHUP
kill -HUP $(pgrep alertmanager)

# Or use API
curl -X POST http://alertmanager:9093/-/reload
```

## Deployment

### AWS Production

AlertManager configuration is deployed via Terraform user-data script:

1. Edit `monitoring/alertmanager/alertmanager.yml`
2. Store secrets in AWS Secrets Manager
3. Run `terraform apply`

### Kubernetes

```bash
# Create secret for webhook URLs
kubectl create secret generic alertmanager-secrets \
  --from-literal=slack-webhook='https://hooks.slack.com/...' \
  --from-literal=pagerduty-key='your-key' \
  -n monitoring

# Update AlertManager config
kubectl create configmap alertmanager-config \
  --from-file=alertmanager.yml \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Restart AlertManager
kubectl rollout restart statefulset/alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring
```

## Related Documentation

- [Monitoring README](../monitoring/README.md)
- [Monitoring Architecture](architecture/diagrams/monitoring-architecture.md)
- [AlertManager Official Docs](https://prometheus.io/docs/alerting/latest/alertmanager/)

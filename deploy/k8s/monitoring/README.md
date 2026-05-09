# Container Security Monitoring Setup

This directory contains Kubernetes manifests for setting up monitoring infrastructure for the container security system.

## Components

### Prometheus
- **Deployment**: `prometheus-deployment.yaml` - Deploys Prometheus server with configuration for scraping container security metrics
- **Config**: `prometheus-config.yaml` - Prometheus configuration with scrape jobs for:
  - Container security webhook metrics
  - Kubernetes API servers
  - Kubernetes nodes and pods
  - Service endpoints

### Grafana
- **Deployment**: `grafana-deployment.yaml` - Deploys Grafana with Prometheus as data source
- **Dashboard**: `grafana-dashboard.yaml` - Pre-configured dashboard for container security metrics visualization

## Deployment

1. Deploy Prometheus:
```bash
kubectl apply -f prometheus-deployment.yaml
kubectl apply -f prometheus-config.yaml
```

2. Deploy Grafana:
```bash
kubectl apply -f grafana-deployment.yaml
kubectl apply -f grafana-dashboard.yaml
```

3. Access Grafana:
```bash
# Port forward Grafana
kubectl port-forward -n container-security svc/grafana 3000:3000

# Open http://localhost:3000
# Default credentials: admin/admin
```

## Metrics Collected

### Admission Webhook Metrics
- `container_security_admission_requests_total`: Total admission requests
- `container_security_admission_requests_allowed_total`: Allowed requests
- `container_security_admission_requests_denied_total`: Denied requests
- `container_security_admission_request_duration_seconds`: Request processing duration
- `container_security_admission_requests_by_reason_total`: Denials by reason and severity
- `container_security_admission_requests_by_pod_total`: Requests by pod, namespace, and decision

### Scanner Metrics
- `container_security_scans_total`: Total container scans
- `container_security_scans_successful_total`: Successful scans
- `container_security_scans_failed_total`: Failed scans
- `container_security_scan_duration_seconds`: Scan duration histogram
- `container_security_vulnerabilities_found`: Vulnerabilities found distribution

### Database Metrics
- `container_security_db_updates_total`: Database update counter
- `container_security_last_db_update_timestamp`: Last database update timestamp

## Notifications

The system supports notifications via Telegram for security violations. Configure in `../webhook/notifications-config.yaml`:

```yaml
enabled: true
botToken: "YOUR_TELEGRAM_BOT_TOKEN"
chatId: "YOUR_TELEGRAM_CHAT_ID"
minSeverity: "medium"
enabledTypes:
  - "security_alert"
  - "policy_violation"
```

### Setting up Telegram Notifications

1. **Create a Telegram Bot:**
   - Go to [@BotFather](https://t.me/BotFather) in Telegram
   - Send `/newbot` and follow the instructions
   - Save the bot token

2. **Get Chat ID:**
   - Send a message to your bot
   - Visit `https://api.telegram.org/bot<YourBOTToken>/getUpdates`
   - Find the "chat" object and note the "id" field

3. **Configure the system:**
   - Set `botToken` to your bot token
   - Set `chatId` to your chat ID
   - Set `enabled: true`

## Dashboard Panels

The Grafana dashboard includes:

1. **Admission Request Rate**: Real-time request throughput
2. **Admission Decisions**: Visual breakdown of allowed/denied requests
3. **Security Violations by Reason**: Table of denial reasons with severity
4. **Scan Performance**: Scan rate and duration percentiles
5. **Vulnerabilities Found**: Heatmap of vulnerability distributions
6. **Database Updates**: Update counters and timestamps
7. **Admission Request Duration**: Processing time heatmap

## Alerting

Configure alerts in Prometheus for:
- High denial rates
- Failed scans
- Security violations
- System availability

Example alert rules:
```yaml
groups:
- name: container-security
  rules:
  - alert: HighSecurityViolationRate
    expr: rate(container_security_admission_requests_denied_total[5m]) > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High rate of security violations"
      description: "Security violations rate is {{ $value }} req/s"
```

# Observability

## Stack Overview

| Tool | Role | Access |
|------|------|--------|
| Prometheus | Metrics collection + alerting | Internal only |
| Grafana | Dashboard visualization | https://grafana.local.dev |
| Loki | Log aggregation | Via Grafana |
| Promtail | Log collector (DaemonSet) | Internal only |

## Metrics with Prometheus

### How it works

Prometheus scrapes `/metrics` endpoints from pods, services, and nodes on a configurable interval (default: 30s).

kube-prometheus-stack provides:
- Prometheus Operator (manages Prometheus config via CRDs)
- ServiceMonitor/PodMonitor CRDs
- AlertManager
- Pre-built dashboards for Kubernetes, nodes, and pods

### Adding metrics to your app

The app-template includes Prometheus instrumentation for FastAPI:

```python
# src/main.py
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()
Instrumentator().instrument(app).expose(app)
```

This automatically exposes:
- `http_requests_total` — request count by method/path/status
- `http_request_duration_seconds` — latency histogram
- `http_requests_in_progress` — active requests

### Creating a ServiceMonitor

The app-template Helm chart includes a ServiceMonitor:

```yaml
# helm/templates/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    release: kube-prometheus-stack  # Must match Prometheus selector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .Values.appName }}
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

### Querying metrics (PromQL examples)

```promql
# Request rate (last 5 min)
rate(http_requests_total{job="payment-service"}[5m])

# Error rate
rate(http_requests_total{job="payment-service", status=~"5.."}[5m])
  / rate(http_requests_total{job="payment-service"}[5m])

# P95 latency
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{job="payment-service"}[5m])
)

# Memory usage
container_memory_working_set_bytes{namespace="payment-service-dev"}

# CPU usage
rate(container_cpu_usage_seconds_total{namespace="payment-service-dev"}[5m])
```

## Dashboards with Grafana

### Accessing Grafana

```
URL: https://grafana.local.dev
Username: admin
Password: prom-operator
```

### Pre-built dashboards

| Dashboard | What it shows |
|-----------|--------------|
| Kubernetes / Compute Resources / Cluster | Cluster-wide CPU/memory |
| Kubernetes / Compute Resources / Namespace | Per-namespace usage |
| Kubernetes / Networking / Namespace | Network traffic |
| Node Exporter Full | Host-level metrics |
| Platform Overview (custom) | All platform components |

### Platform Overview dashboard

`platform/monitoring/grafana/dashboards/platform-overview.json` contains a custom dashboard showing:
- ArgoCD application sync status
- Harbor storage usage
- Vault request rate
- NATS message throughput
- MinIO storage usage
- All pods health

### Adding a new dashboard

1. Create the dashboard in Grafana UI
2. Export as JSON (Share → Export → Save to file)
3. Save to `platform/monitoring/grafana/dashboards/`
4. Add to Grafana ConfigMap in `platform/monitoring/grafana/values.yaml`

## Log Aggregation with Loki

### How it works

1. Promtail (DaemonSet) collects logs from all pods via `/var/log/pods/`
2. Promtail ships logs to Loki with labels: namespace, pod, container, app
3. Grafana queries Loki to display logs alongside metrics

### Viewing logs in Grafana

1. Open Grafana → Explore
2. Select Loki as data source
3. Use LogQL:

```logql
# All logs from payment-service in dev
{namespace="payment-service-dev", app="payment-service"}

# Error logs only
{namespace="payment-service-dev"} |= "ERROR"

# Structured log filtering (JSON logs)
{namespace="payment-service-dev"} | json | level="error"

# Logs from last 5 minutes with rate
rate({namespace="payment-service-dev"}[5m])
```

### Structured logging (recommended)

Apps should output JSON logs for better Loki filtering:

```python
# In your app
import structlog

logger = structlog.get_logger()
logger.info("payment_processed",
    payment_id="123",
    amount=99.99,
    currency="USD",
    duration_ms=45)
```

Output:
```json
{"event": "payment_processed", "payment_id": "123", "amount": 99.99, "currency": "USD", "duration_ms": 45, "level": "info", "timestamp": "2024-01-15T10:30:00Z"}
```

Loki query:
```logql
{namespace="payment-service-dev"} | json | amount > 1000
```

## Alerting

Prometheus AlertManager is deployed with the monitoring stack.

### Example alert rules

```yaml
# platform/monitoring/prometheus/values.yaml
additionalPrometheusRulesMap:
  app-alerts:
    groups:
      - name: app
        rules:
          - alert: HighErrorRate
            expr: |
              rate(http_requests_total{status=~"5.."}[5m]) > 0.1
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High error rate in {{ $labels.job }}"

          - alert: PodCrashLooping
            expr: |
              rate(kube_pod_container_status_restarts_total[15m]) > 0
            for: 5m
            labels:
              severity: critical
```

### Alert routing

For local learning, alerts are visible in AlertManager UI but not sent anywhere. In production, configure:
- Slack webhook
- PagerDuty
- Email

## SLO Tracking

For learning, define a simple SLO for each service:

- **Availability SLO**: 99.9% of requests succeed (non-5xx)
- **Latency SLO**: P95 < 500ms

Track with Prometheus recording rules:

```yaml
- record: job:http_requests:rate5m
  expr: rate(http_requests_total[5m])

- record: job:http_errors:rate5m
  expr: rate(http_requests_total{status=~"5.."}[5m])

- record: job:http_error_rate
  expr: job:http_errors:rate5m / job:http_requests:rate5m
```

The Platform Overview dashboard shows these SLIs for all services.

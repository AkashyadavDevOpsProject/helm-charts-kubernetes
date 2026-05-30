# observability-stack

Complete Kubernetes observability stack for Amazon EKS. Deploys Prometheus, Grafana, Loki, and Alertmanager as a unified Helm release with pre-configured data sources, EKS-specific alert rules (node CPU/memory, pod crash loops, PVC usage, Aurora replication lag, RabbitMQ queue depth), and persistent gp3 storage. Built from the stack running in production SOC 2 Type II compliant FinTech environments.

---

## Architecture

```
┌────────────────────────────────────────────────────┐
│                 EKS Cluster                        │
│                                                    │
│  Pods/Services ──scrape──► Prometheus ──────────┐  │
│                                                  │  │
│  Pods/Services ──push───► Loki                  │  │
│                             │                   │  │
│                             └──datasource──► Grafana│
│                                                  │  │
│  Prometheus ──────────────► Alertmanager         │  │
│                                  │               │  │
│                            Slack/PagerDuty        │  │
└────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Kubernetes | 1.29+ | EKS recommended |
| Helm | 3.14+ | |
| gp3 StorageClass | — | Must exist in the cluster (`kubectl get sc`) |
| Prometheus Operator CRDs | — | Required for PrometheusRule and ServiceMonitor |
| metrics-server | 0.6+ | For HPA metrics (not strictly required here) |

Check that gp3 is available:
```bash
kubectl get storageclass gp3
```

---

## Installation

```bash
# Add required Helm repos and update dependencies
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Download sub-chart dependencies
helm dependency update charts/observability-stack/

# Install with minimum required values
helm install observability akashyadav/observability-stack \
  --set grafana.adminPassword=YourSecurePassword123 \
  --namespace monitoring \
  --create-namespace
```

Install with Slack alerts enabled:
```bash
helm install observability akashyadav/observability-stack \
  --set grafana.adminPassword=YourSecurePassword123 \
  --set prometheus.alertmanager.config.receivers[0].slack_configs[0].api_url=https://hooks.slack.com/services/T00/B00/xxx \
  --namespace monitoring \
  --create-namespace
```

---

## Values Reference

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| `prometheus.enabled` | Deploy Prometheus | bool | `true` | No |
| `prometheus.server.retention` | Metric retention period | string | `15d` | No |
| `prometheus.server.persistentVolume.storageClass` | StorageClass for Prometheus TSDB | string | `gp3` | No |
| `prometheus.server.persistentVolume.size` | Prometheus PVC size | string | `50Gi` | No |
| `prometheus.alertmanager.enabled` | Deploy Alertmanager | bool | `true` | No |
| `prometheus.alertmanager.config.receivers[0].slack_configs[0].api_url` | Slack webhook URL | string | `""` | No |
| `prometheus.alertmanager.config.receivers[1].pagerduty_configs[0].service_key` | PagerDuty integration key | string | `""` | No |
| `grafana.enabled` | Deploy Grafana | bool | `true` | No |
| `grafana.adminPassword` | Grafana admin password | string | `""` | **Yes** |
| `grafana.persistence.storageClassName` | StorageClass for Grafana data | string | `gp3` | No |
| `grafana.persistence.size` | Grafana PVC size | string | `10Gi` | No |
| `loki.enabled` | Deploy Loki | bool | `true` | No |
| `loki.singleBinary.persistence.storageClass` | StorageClass for Loki logs | string | `gp3` | No |
| `loki.singleBinary.persistence.size` | Loki PVC size | string | `50Gi` | No |
| `rabbitmq.monitoring.enabled` | Deploy RabbitMQ ServiceMonitor | bool | `false` | No |
| `rabbitmq.monitoring.namespace` | Namespace where RabbitMQ runs | string | `""` | If RMQ enabled |

---

## Usage Examples

### Example 1 — Standard install with Slack alerts

```bash
helm install observability akashyadav/observability-stack \
  --set grafana.adminPassword=SecurePassword \
  --set "prometheus.alertmanager.config.receivers[0].slack_configs[0].api_url=https://hooks.slack.com/services/..." \
  --namespace monitoring --create-namespace
```

### Example 2 — Larger storage for high-traffic environment

```yaml
# values-production.yaml
prometheus:
  server:
    retention: 30d
    persistentVolume:
      size: 200Gi

loki:
  singleBinary:
    persistence:
      size: 200Gi

grafana:
  adminPassword: ""  # Set via --set
  persistence:
    size: 20Gi
```

```bash
helm install observability akashyadav/observability-stack \
  -f values-production.yaml \
  --set grafana.adminPassword=SecurePassword \
  --namespace monitoring
```

### Example 3 — With RabbitMQ monitoring enabled

```bash
helm install observability akashyadav/observability-stack \
  --set grafana.adminPassword=SecurePassword \
  --set rabbitmq.monitoring.enabled=true \
  --set rabbitmq.monitoring.namespace=message-bus \
  --namespace monitoring
```

---

## Adding Custom Dashboards via ConfigMap

```bash
# Create a ConfigMap from your Grafana dashboard JSON export
kubectl create configmap my-service-dashboard \
  --from-file=my-service.json=/path/to/dashboard.json \
  --namespace monitoring

# Label it for Grafana auto-discovery
kubectl label configmap my-service-dashboard \
  grafana_dashboard=1 \
  --namespace monitoring
```

---

## Accessing Grafana

```bash
kubectl port-forward svc/observability-grafana 3000:80 -n monitoring
# Open http://localhost:3000
# Username: admin / Password: (your grafana.adminPassword value)
```

---

## Upgrade Notes

```bash
# Update dependencies first
helm dependency update charts/observability-stack/

# Upgrade
helm upgrade observability akashyadav/observability-stack \
  -f values-production.yaml \
  --set grafana.adminPassword=SecurePassword \
  --namespace monitoring \
  --atomic --timeout 10m
```

---

## Troubleshooting

**Prometheus PVC stuck in `Pending`**
- The `gp3` StorageClass does not exist. Create it or change `prometheus.server.persistentVolume.storageClass` to an existing class.
- Check: `kubectl get storageclass` and `kubectl describe pvc -n monitoring`

**Grafana shows "Data source connection failed" for Prometheus**
- The Prometheus server URL in the datasource may be wrong. The default assumes the release is named `observability`. If you used a different release name, update `grafana.datasources.datasources.yaml.datasources[0].url` accordingly.

**Alertmanager not sending Slack notifications**
- Verify `prometheus.alertmanager.config.receivers[0].slack_configs[0].api_url` is set.
- Check Alertmanager config: `kubectl exec -n monitoring deploy/observability-alertmanager -- amtool config show`
- Test the Slack webhook manually: `curl -X POST -d '{"text":"test"}' YOUR_WEBHOOK_URL`

**PrometheusRule alerts not appearing in Prometheus**
- Prometheus Operator CRDs must be installed. Check: `kubectl get crd prometheusrules.monitoring.coreos.com`
- If missing, install kube-prometheus-stack CRDs first.

**Scrape targets missing for application pods**
- Pods must have the `prometheus.io/scrape: "true"` annotation.
- Check the microservice chart's `podAnnotations` — it sets this by default.

# Helm Charts Usage Guide

Comprehensive guide for deploying and operating production-grade infrastructure using the `akashyadav` Helm chart repository on Amazon EKS.

---

## Overview

This repository provides six production-grade Helm charts built from real FinTech infrastructure experience. Each chart is independently deployable, IRSA-ready, and designed to work together as a complete platform stack.

| Chart | Purpose | Typical Namespace |
|-------|---------|-------------------|
| `microservice` | Deploy any containerized service | `production`, `staging` |
| `observability-stack` | Prometheus + Grafana + Loki + Alertmanager | `monitoring` |
| `eks-autoscaler` | Karpenter + HPA for EKS node scaling | `karpenter` |
| `devsecops-pipeline` | GitLab Runner + Trivy + OPA + Vault | `devops` |
| `postgresql-ha` | PostgreSQL HA + PgBouncer + S3 backup | `data` |
| `dr-failover-controller` | Multi-region DR health check + Route 53 failover | `dr` |

---

## Prerequisites

### Tools

```bash
# Helm 3.14+
helm version

# kubectl configured against your EKS cluster
kubectl cluster-info

# AWS CLI v2
aws --version

# Verify EKS connectivity
kubectl get nodes
```

### EKS Cluster Requirements

| Requirement | Why |
|-------------|-----|
| EKS 1.29+ | Required for AL2023 AMI and Karpenter v1 API |
| gp3 StorageClass | Used by Prometheus, Loki, Grafana, PostgreSQL |
| AWS Load Balancer Controller | Required for `ingress.enabled: true` in microservice chart |
| metrics-server | Required for HPA to function |
| Karpenter 0.34+ | Required for eks-autoscaler chart |
| Prometheus Operator CRDs | Required for ServiceMonitor and PrometheusRule resources |

---

## Installing the Repository

```bash
# Add the Helm repository
helm repo add akashyadav \
  https://akashyadavdevopsproject.github.io/helm-charts-kubernetes

# Update the local cache
helm repo update

# Browse available charts
helm search repo akashyadav

# Inspect a chart before installing
helm show values akashyadav/microservice
helm show chart akashyadav/postgresql-ha
```

---

## Common Deployment Patterns

### Pattern 1 — Deploy a Node.js microservice with IRSA

This pattern is the most common use case: deploying a stateless service that needs AWS API access.

**Create a values file:**

```yaml
# values-payments-api.yaml
image:
  repository: 123456789.dkr.ecr.ap-south-1.amazonaws.com/payments-api
  tag: v1.4.2
  pullPolicy: IfNotPresent

replicaCount: 3

serviceAccount:
  create: true
  annotations:
    # IRSA: grants this service access to SQS and DynamoDB
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/payments-api-role

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 65

ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
  hosts:
    - host: payments-api.internal.example.com
      paths:
        - path: /
          pathType: Prefix

networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
    - from:
        - namespaceSelector:
            matchLabels:
              name: api-gateway
```

**Deploy:**

```bash
helm install payments-api akashyadav/microservice \
  -f values-payments-api.yaml \
  --namespace production \
  --create-namespace \
  --atomic \
  --timeout 5m
```

**Verify:**

```bash
kubectl get pods -n production -l app.kubernetes.io/name=microservice
kubectl get hpa -n production
kubectl get networkpolicy -n production
```

---

### Pattern 2 — Full observability stack

Deploy the complete monitoring platform for your EKS cluster.

```bash
# Step 1: Add upstream chart repos and update dependencies
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Step 2 (if using local chart): download sub-chart dependencies
helm dependency update charts/observability-stack/

# Step 3: Create a values file
cat > values-monitoring.yaml <<'EOF'
prometheus:
  server:
    retention: 30d
    persistentVolume:
      size: 100Gi

grafana:
  adminPassword: ""  # set via --set below
  persistence:
    size: 20Gi

loki:
  singleBinary:
    persistence:
      size: 100Gi

rabbitmq:
  monitoring:
    enabled: false
EOF

# Step 4: Install
helm install observability akashyadav/observability-stack \
  -f values-monitoring.yaml \
  --set grafana.adminPassword=YourSecurePassword \
  --set "prometheus.alertmanager.config.receivers[0].slack_configs[0].api_url=https://hooks.slack.com/services/..." \
  --namespace monitoring \
  --create-namespace \
  --atomic --timeout 10m

# Step 5: Access Grafana
kubectl port-forward svc/observability-grafana 3000:80 -n monitoring
# Open http://localhost:3000 — admin / YourSecurePassword
```

---

### Pattern 3 — Autoscaling configuration for cost-optimised EKS

Configure Karpenter to mix On-Demand and Spot nodes with Graviton3 instances.

```bash
# Install Karpenter first (not covered by this chart — use the official Karpenter Helm chart)
# Then deploy node pools:

helm install autoscaler akashyadav/eks-autoscaler \
  --set karpenter.clusterName=prod-eks \
  --set karpenter.clusterEndpoint=https://XXXXXXXX.gr7.ap-south-1.eks.amazonaws.com \
  --set karpenter.interruptionQueue=prod-eks-karpenter-interruption \
  --set ec2NodeClass.role=KarpenterNodeRole-prod-eks \
  --set "ec2NodeClass.subnetSelectorTerms[0].tags.karpenter\.sh/discovery=prod-eks" \
  --set "ec2NodeClass.securityGroupSelectorTerms[0].tags.karpenter\.sh/discovery=prod-eks" \
  --set ec2NodeClass.tags.Environment=production \
  --set ec2NodeClass.tags.CostCenter=platform \
  --namespace karpenter \
  --atomic --timeout 5m

# Verify NodePools are accepted by Karpenter
kubectl get nodepools
kubectl get ec2nodeclasses
```

**To use Spot nodes in a workload, add this toleration:**

```yaml
tolerations:
  - key: karpenter.sh/capacity-type
    value: spot
    effect: NoSchedule
```

---

### Pattern 4 — DR controller setup

Multi-region failover for critical payment infrastructure.

```bash
# Step 1: Create the IRSA role with the required Route 53, SNS, RDS permissions
# (done via Terraform/CloudFormation — see AWS documentation)

# Step 2: Create the SNS topic (if not already exists)
aws sns create-topic --name dr-alerts --region ap-south-1

# Step 3: Install the DR controller
helm install dr-controller akashyadav/dr-failover-controller \
  --set controller.healthChecks.primary.endpoint=https://api.example.com/health \
  --set controller.healthChecks.aurora.clusterIdentifier=prod-aurora \
  --set controller.failover.route53.hostedZoneId=Z1234567890ABCDE \
  --set controller.failover.route53.primaryRecordName=api.example.com \
  --set controller.failover.route53.drRecordName=api-dr.example.com \
  --set controller.failover.sns.topicArn=arn:aws:sns:ap-south-1:123456789:dr-alerts \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/dr-controller \
  --namespace dr \
  --create-namespace

# Step 4: Verify health checks are running
kubectl get cronjob -n dr
kubectl logs -n dr -l app.kubernetes.io/component=healthcheck --tail=30
```

---

## Multi-Environment Workflow

Maintain separate values files per environment. Never change code between environments — only configuration.

```
                   ┌──────────────┐
                   │  values.yaml │  (chart defaults — no env-specific values)
                   └──────┬───────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
┌────────────────┐ ┌───────────────┐ ┌──────────────────┐
│ values-dev.yaml│ │values-staging │ │values-prod.yaml  │
│                │ │    .yaml      │ │                  │
│ replicaCount:1 │ │replicaCount:2 │ │ replicaCount: 5  │
│ resources: low │ │resources: med │ │ resources: prod  │
│ HPA: disabled  │ │HPA: enabled   │ │ HPA: enabled     │
│ network: open  │ │network: std   │ │ network: strict  │
└────────────────┘ └───────────────┘ └──────────────────┘
```

**Example workflow:**

```bash
# Deploy to dev (fast iteration, minimal resources)
helm upgrade --install my-service akashyadav/microservice \
  -f values-dev.yaml \
  --namespace dev --create-namespace

# Promote to staging (same image tag, staging config)
helm upgrade --install my-service akashyadav/microservice \
  -f values-staging.yaml \
  --set image.tag=v1.2.3 \
  --namespace staging

# Deploy to production (full HA, strict security)
helm upgrade --install my-service akashyadav/microservice \
  -f values-prod.yaml \
  --set image.tag=v1.2.3 \
  --namespace production \
  --atomic \
  --timeout 10m
```

---

## Upgrading Charts

```bash
# 1. Preview changes (requires helm-diff plugin)
helm diff upgrade my-service akashyadav/microservice \
  -f values-prod.yaml --namespace production

# 2. Upgrade with automatic rollback on failure
helm upgrade my-service akashyadav/microservice \
  -f values-prod.yaml \
  --namespace production \
  --atomic \
  --timeout 10m

# 3. Check history
helm history my-service -n production

# 4. Manual rollback to a previous revision
helm rollback my-service 2 -n production --wait --timeout 5m
```

---

## Troubleshooting Common Issues

**1. Pods stuck in `Pending` — insufficient resources**
```bash
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 5 Events
# Look for: Insufficient cpu / Insufficient memory / no nodes matched
# Fix: Check node capacity or increase Karpenter NodePool limits
```

**2. `ImagePullBackOff` — cannot pull container image**
```bash
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 10 Events
# Check: ECR URI is correct, IRSA role has ECR pull permissions
# Check: imagePullSecrets is set if using a private registry
```

**3. `CrashLoopBackOff` — application keeps restarting**
```bash
kubectl logs POD_NAME -n NAMESPACE --previous
# Common cause: readOnlyRootFilesystem: true blocks app writing to disk
# Fix: mount emptyDir volumes for writable paths (/tmp, logs directory)
```

**4. HPA showing `<unknown>` metrics**
```bash
kubectl top pods -n NAMESPACE
# If this fails: metrics-server is not installed
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**5. `helm upgrade` failing — revision stuck**
```bash
helm history RELEASE_NAME -n NAMESPACE
# If status is 'pending-upgrade', force a rollback
helm rollback RELEASE_NAME 0 -n NAMESPACE
```

**6. NetworkPolicy blocking traffic unexpectedly**
```bash
kubectl get networkpolicy -n NAMESPACE -o yaml
# Temporarily disable to confirm: set networkPolicy.enabled: false
# Add the source namespace to networkPolicy.ingress in values
```

**7. PVC stuck in `Pending`**
```bash
kubectl describe pvc PVC_NAME -n NAMESPACE
# Check: StorageClass exists: kubectl get sc
# Check: AWS EBS CSI driver is installed in the cluster
```

**8. IRSA not working — `AccessDenied` from pods**
```bash
kubectl exec POD_NAME -n NAMESPACE -- aws sts get-caller-identity
# Should show the IRSA role ARN, not the node instance role
# Fix: Ensure serviceAccount.annotations contains the correct role-arn
# Fix: OIDC provider must be configured for the EKS cluster
```

**9. Helm release stuck in `failed` state**
```bash
helm status RELEASE_NAME -n NAMESPACE
helm rollback RELEASE_NAME 0 -n NAMESPACE --force
```

**10. Secret values accidentally committed to Git**
```bash
# Immediately rotate the exposed secret
# Use SOPS, AWS Secrets Manager, or Vault for secret management
# Use --set for sensitive values instead of values files:
helm upgrade my-service akashyadav/microservice \
  -f values-prod.yaml \
  --set image.repository=REPO \  # non-sensitive in values file
  --set somePassword=SECRET       # sensitive via --set (not in file)
```

---

## Contributing

### Adding a New Chart

```
charts/my-new-chart/
├── Chart.yaml          # apiVersion: v2, version: 1.0.0
├── values.yaml         # Comment every single value
├── README.md           # Values table, 3 usage examples, troubleshooting
└── templates/
    ├── _helpers.tpl    # Define all 5 standard labels
    ├── NOTES.txt       # Useful post-install instructions
    └── *.yaml          # Use apps/v1, policy/v1 — no deprecated APIs
```

### Pull Request Checklist

Before opening a PR:

- [ ] `helm lint charts/my-new-chart/` passes with zero errors and zero warnings
- [ ] Every value in `values.yaml` has a comment
- [ ] No hardcoded AWS account IDs, ARNs, or cluster names
- [ ] All sensitive values default to `""` with a comment pointing to `--set` or `existingSecret`
- [ ] Security defaults: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`
- [ ] `README.md` includes a values table and at least 3 real usage examples
- [ ] `NOTES.txt` shows access method, key config summary, and next steps
- [ ] GitLab CI `.gitlab-ci-helm.yml` lint stage passes for this chart

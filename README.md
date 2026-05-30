# Production-Grade Helm Charts for AWS EKS

[![Helm](https://img.shields.io/badge/Helm-v3.14+-0F1689?logo=helm&logoColor=white)](https://helm.sh)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29%2B-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![AWS EKS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/eks/)
[![GitLab CI](https://img.shields.io/badge/CI%2FCD-GitLab-FC6D26?logo=gitlab&logoColor=white)](https://gitlab.com)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![License](https://img.shields.io/badge/License-Apache%202.0-4CAF50)](LICENSE)
[![Charts](https://img.shields.io/badge/Charts-6%20stable-blue)](charts/)

> Six production-grade Helm charts built from 3.3 years of real FinTech infrastructure experience on AWS EKS — processing live payment transactions, maintaining SOC 2 Type II compliance, and surviving on-call incidents at scale. Every default is a deliberate production decision, not a tutorial placeholder.

---

## Table of Contents

- [Platform Overview](#platform-overview)
- [Chart Catalog](#chart-catalog)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Install Commands](#install-commands)
- [Platform Architecture](#platform-architecture)
- [CI/CD Pipeline](#cicd-pipeline)
- [Design Principles](#design-principles)
- [Repository Structure](#repository-structure)
- [Documentation](#documentation)
- [Author](#author)

---

## Platform Overview

This repository provides a complete Kubernetes platform stack for AWS EKS. The six charts are designed to work independently or together — deploy only what you need, with values files for each environment.

```
┌──────────────────────── AWS EKS Cluster (ap-south-1) ──────────────────────────┐
│                                                                                 │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐              │
│  │  microservice   │   │  microservice   │   │  microservice   │  ← Chart 1   │
│  │  (payments-api) │   │  (ledger-svc)   │   │  (kyc-service)  │              │
│  └────────┬────────┘   └────────┬────────┘   └────────┬────────┘              │
│           │                     │                     │                         │
│           └─────────────────────┼─────────────────────┘                        │
│                                 │ metrics + logs                                │
│  ┌──────────────────────────────▼──────────────────────────────────┐           │
│  │              observability-stack (Chart 2)                       │  ← Chart 2│
│  │   Prometheus ──► Grafana    Loki ──► Grafana    Alertmanager    │           │
│  └──────────────────────────────────────────────────────────────────┘           │
│                                                                                 │
│  ┌────────────────────────┐    ┌─────────────────────────────────┐             │
│  │   eks-autoscaler       │    │   postgresql-ha                 │  ← Charts   │
│  │   Chart 3              │    │   Chart 5                       │    3 + 5    │
│  │  Karpenter NodePools   │    │  Primary ──► Replica × 2       │             │
│  │  On-Demand + Spot      │    │  PgBouncer  S3 Backup CronJob  │             │
│  └────────────────────────┘    └─────────────────────────────────┘             │
│                                                                                 │
│  ┌────────────────────────┐    ┌─────────────────────────────────┐             │
│  │   devsecops-pipeline   │    │   dr-failover-controller        │  ← Charts   │
│  │   Chart 4              │    │   Chart 6                       │    4 + 6    │
│  │  GitLab Runner × 5     │    │  Health CronJob → Route 53      │             │
│  │  Trivy  OPA  Vault     │    │  ap-south-1 → ap-south-2        │             │
│  └────────────────────────┘    └─────────────────────────────────┘             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Chart Catalog

| # | Chart | What It Deploys | Version |
|---|-------|-----------------|---------|
| 1 | [**microservice**](charts/microservice/) | Reusable EKS deployment template — HPA, PDB, IRSA, NetworkPolicy, Secrets Store CSI, topology spread across AZs | `1.0.0` |
| 2 | [**observability-stack**](charts/observability-stack/) | Prometheus (30d retention) + Grafana + Loki + Alertmanager with 8 production EKS alert rules | `1.0.0` |
| 3 | [**eks-autoscaler**](charts/eks-autoscaler/) | Karpenter NodePools for Graviton3 On-Demand + Spot + GPU, EC2NodeClass with IMDSv2, AL2023 | `1.0.0` |
| 4 | [**devsecops-pipeline**](charts/devsecops-pipeline/) | GitLab Kubernetes executor runners + Trivy scanner + OPA Rego policies + HashiCorp Vault agent | `1.0.0` |
| 5 | [**postgresql-ha**](charts/postgresql-ha/) | PostgreSQL 16 HA (repmgr) + PgBouncer pooling + daily pg_dump → S3 + postgres_exporter | `1.0.0` |
| 6 | [**dr-failover-controller**](charts/dr-failover-controller/) | Multi-region health check CronJob + Route 53 DNS failover + SNS alerts — RPO 3h / RTO 30min | `1.0.0` |

---

## Quick Start

```bash
# 1. Add the repo
helm repo add akashyadav \
  https://akashyadavdevopsproject.github.io/helm-charts-kubernetes
helm repo update

# 2. Browse charts
helm search repo akashyadav

# 3. Inspect values before installing
helm show values akashyadav/microservice
```

---

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| [Helm](https://helm.sh/docs/intro/install/) | 3.14+ | Chart installation |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.29+ | Cluster interaction |
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | ECR auth, IRSA setup |
| EKS Cluster | 1.29+ | Deployment target |
| gp3 StorageClass | — | Required by charts 2, 5 |
| [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) | 2.x | Required for `ingress.enabled: true` |
| [metrics-server](https://github.com/kubernetes-sigs/metrics-server) | 0.6+ | Required for HPA |
| [Karpenter](https://karpenter.sh/) | 0.34+ | Required for Chart 3 |
| Prometheus Operator CRDs | — | Required for ServiceMonitor / PrometheusRule |

---

## Install Commands

### Chart 1 — microservice

```bash
helm upgrade --install payments-api akashyadav/microservice \
  --set image.repository=123456789.dkr.ecr.ap-south-1.amazonaws.com/payments-api \
  --set image.tag=v1.4.2 \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/payments-api \
  --namespace production --create-namespace \
  -f charts/microservice/values-production.yaml
```

### Chart 2 — observability-stack

```bash
# Update sub-chart dependencies first
helm dependency update charts/observability-stack/

helm upgrade --install observability akashyadav/observability-stack \
  --set grafana.adminPassword=$GRAFANA_PASSWORD \
  --set "prometheus.alertmanager.config.receivers[0].slack_configs[0].api_url=$SLACK_WEBHOOK" \
  --namespace monitoring --create-namespace \
  -f charts/observability-stack/values-production.yaml
```

### Chart 3 — eks-autoscaler

```bash
helm upgrade --install autoscaler akashyadav/eks-autoscaler \
  --set karpenter.clusterName=$EKS_CLUSTER_NAME \
  --set karpenter.clusterEndpoint=$EKS_CLUSTER_ENDPOINT \
  --set karpenter.interruptionQueue=${EKS_CLUSTER_NAME}-karpenter-interruption \
  --set ec2NodeClass.role=KarpenterNodeRole-${EKS_CLUSTER_NAME} \
  --set "ec2NodeClass.subnetSelectorTerms[0].tags.karpenter\.sh/discovery=$EKS_CLUSTER_NAME" \
  --set "ec2NodeClass.securityGroupSelectorTerms[0].tags.karpenter\.sh/discovery=$EKS_CLUSTER_NAME" \
  --namespace karpenter --create-namespace \
  -f charts/eks-autoscaler/values-production.yaml
```

### Chart 4 — devsecops-pipeline

```bash
helm upgrade --install devsecops akashyadav/devsecops-pipeline \
  --set gitlab.runner.gitlabUrl=$GITLAB_URL \
  --set gitlab.runner.runnerToken=$GITLAB_RUNNER_TOKEN \
  --set vault.agent.address=$VAULT_ADDR \
  --set vault.agent.role=$VAULT_ROLE \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/runner-irsa \
  --namespace devops --create-namespace \
  -f charts/devsecops-pipeline/values-production.yaml
```

### Chart 5 — postgresql-ha

```bash
helm upgrade --install postgres akashyadav/postgresql-ha \
  --set postgresql.auth.postgresPassword=$PG_SUPERUSER_PASSWORD \
  --set postgresql.auth.username=appuser \
  --set postgresql.auth.password=$PG_APP_PASSWORD \
  --set postgresql.auth.database=appdb \
  --set backup.s3Bucket=$PG_BACKUP_BUCKET \
  --set backup.s3Region=ap-south-1 \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/pg-backup-irsa \
  --namespace data --create-namespace \
  -f charts/postgresql-ha/values-production.yaml
```

### Chart 6 — dr-failover-controller

```bash
helm upgrade --install dr-controller akashyadav/dr-failover-controller \
  --set controller.healthChecks.primary.endpoint=$PRIMARY_HEALTH_URL \
  --set controller.healthChecks.aurora.clusterIdentifier=$AURORA_CLUSTER_ID \
  --set controller.failover.route53.hostedZoneId=$ROUTE53_ZONE_ID \
  --set controller.failover.route53.primaryRecordName=api.example.com \
  --set controller.failover.route53.drRecordName=api-dr.example.com \
  --set controller.failover.sns.topicArn=$DR_SNS_TOPIC_ARN \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/dr-controller \
  --namespace dr --create-namespace \
  -f charts/dr-failover-controller/values-production.yaml
```

---

## Platform Architecture

### Multi-Environment Deployment Flow

```
Git push → GitLab CI (.gitlab-ci-helm.yml)
              │
    ┌─────────┼──────────┐
    ▼         ▼          ▼
  lint      package   publish-to-s3
  (helm     (.tgz     (index.yaml
  lint      all 6     + charts →
  --strict) charts)   S3 bucket)
              │
              ▼
         ArgoCD picks up new chart version
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
   dev     staging   production
  (auto)   (auto)   (manual gate)
```

### Secret Delivery Pattern

All sensitive values (passwords, API keys, tokens) follow one of two patterns — never plaintext in values files:

```
Pattern A — --set at deploy time (from GitLab CI/CD variables):
  helm upgrade ... --set postgresql.auth.postgresPassword=$PG_PASSWORD

Pattern B — existingSecret reference (pre-created in cluster):
  postgresql.auth.existingSecret: pg-credentials-secret
```

### Node Strategy (Karpenter)

```
Payment APIs, DBs, System workloads
        │
        ▼
  On-Demand pool        Spot pool
  (Graviton3 m7g)       (m7g/m6g/c7g/r7g — 16 types)
  weight: 10            weight: 50
  consolidate: 5m       consolidate: WhenEmpty
        │                     │
        └──────────┬───────────┘
                   ▼
          Karpenter NodeClaims
          AL2023 + gp3 + IMDSv2
          imdsHopLimit: 2 (IRSA requirement)
```

---

## CI/CD Pipeline

The repository ships with [`.gitlab-ci-helm.yml`](.gitlab-ci-helm.yml) — a GitLab CI/CD pipeline with three stages triggered on every push to `main`.

```yaml
stages:
  - lint          # helm lint --strict + kubeconform schema validation (K8s 1.32)
  - package       # helm package → .tgz + helm repo index regeneration
  - publish-to-s3 # aws s3 cp → S3 bucket serving the Helm repository
```

**Required GitLab CI/CD variables** (set in Settings → CI/CD → Variables, masked + protected):

| Variable | Example | Purpose |
|----------|---------|---------|
| `AWS_ACCESS_KEY_ID` | `AKIA...` | S3 publish access |
| `AWS_SECRET_ACCESS_KEY` | `****` | S3 publish access |
| `AWS_DEFAULT_REGION` | `ap-south-1` | S3 bucket region |
| `S3_BUCKET` | `my-helm-charts` | Bucket name (no `s3://`) |
| `S3_PREFIX` | `helm-charts` | Key prefix inside bucket |

---

## Design Principles

### Security-First Defaults

Every chart ships hardened out of the box — no opt-in required:

```yaml
securityContext:
  runAsNonRoot: true           # Kubernetes rejects root containers
  runAsUser: 1000              # Consistent non-root UID across all services
  readOnlyRootFilesystem: true # Writes require explicit emptyDir volumes
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]                # Zero Linux capabilities — add back only what's needed
```

NetworkPolicy is enabled by default — all inter-namespace traffic is denied except explicitly allowed sources. In SOC 2 environments, this is not negotiable.

### IRSA Over Instance Profiles

Every chart that touches AWS APIs uses IRSA (IAM Roles for Service Accounts) — never the node instance profile:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/SERVICE-role
```

Each workload gets its own least-privilege role. The backup CronJob can only write to its S3 bucket. The DR controller can only call Route 53 and SNS. The payment API can only access its own DynamoDB table and SQS queue.

### Production Defaults That Aren't Obvious

| Setting | Value | Why |
|---------|-------|-----|
| `terminationGracePeriodSeconds` | `60` | Payment transactions need up to 30s to complete; preStop sleep 10s for ALB drain |
| `autoscaling.targetCPUUtilizationPercentage` | `65%` | Payment spikes are sudden — scale before latency degrades, not after |
| `karpenter.consolidateAfter` | `5m` | JVM startup is 60s; 30s consolidation recycles nodes before apps are ready |
| `pgbouncer.poolMode` | `transaction` | Correct for stateless web apps; `session` needed only for advisory locks |
| `backup.retentionDays` | `90` | Exceeds SOC 2 30-day minimum; supports quarterly audit data requests |
| `imdsHopLimit` | `2` | AL2023 default of `1` silently breaks IRSA for all pod-level AWS API calls |
| `hpa.scaleDownStabilizationWindowSeconds` | `600` | Prevents flapping during hourly traffic wave patterns common in IST timezone |

### Multi-Environment Without Duplication

Each chart ships with two values files:

- `values.yaml` — safe defaults, all sensitive values empty, every line commented
- `values-production.yaml` — production overrides with comments explaining **why** each value differs

```bash
# Dev: minimal resources, relaxed security for fast iteration
helm install my-svc akashyadav/microservice -f values-dev.yaml

# Production: hardened, scaled, monitored
helm upgrade --install my-svc akashyadav/microservice \
  -f charts/microservice/values-production.yaml \
  --set image.tag=$CI_COMMIT_SHA \
  --atomic --timeout 10m
```

---

## Repository Structure

```
helm-charts-kubernetes/
│
├── .gitlab-ci-helm.yml              # GitLab CI/CD: lint → package → publish-to-s3
├── README.md                        # This file
├── index.yaml                       # Helm repository index (auto-regenerated by CI)
│
├── charts/
│   ├── microservice/                # Chart 1 — Reusable microservice template
│   │   ├── Chart.yaml
│   │   ├── values.yaml              # Defaults with comments on every value
│   │   ├── values-production.yaml   # Production overrides (ap-south-1 FinTech)
│   │   ├── README.md                # Values table + 3 usage examples
│   │   ├── .helmignore
│   │   └── templates/
│   │       ├── _helpers.tpl         # All 5 standard K8s labels + SA name
│   │       ├── NOTES.txt            # Post-install access instructions
│   │       ├── deployment.yaml      # HPA, PDB, CSI, probes, lifecycle
│   │       ├── hpa.yaml             # autoscaling/v2 CPU + memory targets
│   │       ├── pdb.yaml             # policy/v1 PodDisruptionBudget
│   │       ├── networkpolicy.yaml   # Deny-all ingress except allowed namespaces
│   │       ├── ingress.yaml         # ALB Ingress Controller annotations
│   │       ├── service.yaml
│   │       └── serviceaccount.yaml  # IRSA annotation support
│   │
│   ├── observability-stack/         # Chart 2 — Prometheus + Grafana + Loki
│   ├── eks-autoscaler/              # Chart 3 — Karpenter NodePools
│   ├── devsecops-pipeline/          # Chart 4 — GitLab Runner + security tooling
│   ├── postgresql-ha/               # Chart 5 — PostgreSQL HA + PgBouncer
│   └── dr-failover-controller/      # Chart 6 — Multi-region DR failover
│
└── docs/
    └── usage-guide.md               # End-to-end deployment patterns + troubleshooting
```

---

## Documentation

| Resource | Description |
|----------|-------------|
| [docs/usage-guide.md](docs/usage-guide.md) | Complete deployment patterns, multi-environment workflow, upgrade procedure, 10 common troubleshooting scenarios |
| [charts/microservice/README.md](charts/microservice/README.md) | Full values reference table, 3 real usage examples, troubleshooting |
| [charts/observability-stack/README.md](charts/observability-stack/README.md) | Architecture diagram, Grafana access, custom dashboard setup |
| [charts/eks-autoscaler/README.md](charts/eks-autoscaler/README.md) | Spot vs On-Demand decision guide, Karpenter prerequisites, IMDSv2 explained |
| [charts/devsecops-pipeline/README.md](charts/devsecops-pipeline/README.md) | Runner registration verification, OPA policy enforcement, Vault injection |
| [charts/postgresql-ha/README.md](charts/postgresql-ha/README.md) | Replication monitoring, backup/restore procedure, PgBouncer connection guide |
| [charts/dr-failover-controller/README.md](charts/dr-failover-controller/README.md) | Manual failover procedure, failback steps, testing without triggering |

---

## Author

**Akash Yadav**
Senior DevOps & Cloud Infrastructure Engineer

3.3 years designing and operating production Kubernetes infrastructure on AWS EKS for a FinTech payment platform. Day-to-day work includes EKS cluster lifecycle management, GitLab CI/CD pipeline architecture, Karpenter cost optimisation, infrastructure-as-code with Terraform, and on-call ownership for services processing real payment transactions.

**Core stack:** AWS EKS · Karpenter · GitLab CI/CD · ArgoCD · Helm · Terraform · Prometheus · Grafana · HashiCorp Vault · PostgreSQL · Jenkins

**Connect:**
- GitHub: [github.com/AkashyadavDevOpsProject](https://github.com/AkashyadavDevOpsProject)
- LinkedIn: [linkedin.com/in/akash-yadav-devops](https://linkedin.com/in/akash-yadav-devops)

---

## License

Apache 2.0 — see [LICENSE](LICENSE)

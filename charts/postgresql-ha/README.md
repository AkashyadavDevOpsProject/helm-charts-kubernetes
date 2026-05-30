# postgresql-ha

PostgreSQL High Availability on Kubernetes with streaming replication (1 primary + N replicas via repmgr), PgBouncer connection pooling, automated daily S3 backup via CronJob, and Prometheus metrics exporter. Implements the stateful database pattern for production EKS clusters — gp3 persistent storage, NetworkPolicy access control, and IRSA-based S3 authentication for backups.

---

## Architecture

```
                   ┌──────────────────────────────────┐
  Applications ──► │  PgBouncer (2 replicas)           │
                   │  transaction pool — max 1000 conn │
                   └──────────────┬───────────────────┘
                                  │ max 25 conn
                   ┌──────────────▼───────────────────┐
                   │  PostgreSQL Primary (1 pod)        │
                   │  Writes + reads                   │
                   └──────────────┬───────────────────┘
                    streaming     │
                    replication   │
                   ┌──────────────▼───────────────────┐
                   │  PostgreSQL Replicas (N-1 pods)   │
                   │  Read-only queries                │
                   └──────────────────────────────────┘

  Backup CronJob ──► pg_dump ──► S3 (daily, 30-day retention)
  Prometheus ──────► postgres_exporter (port 9187)
```

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| EKS cluster 1.29+ | |
| gp3 StorageClass | `kubectl get sc gp3` |
| IRSA role for backup | S3 `PutObject` + `GetObject` + `ListBucket` on backup bucket |
| Prometheus Operator CRDs | Required if `metrics.serviceMonitor.enabled: true` |

---

## Installation

```bash
# Minimum — single database with HA and backup
helm install postgres akashyadav/postgresql-ha \
  --set postgresql.auth.postgresPassword=SuperSecretPassword \
  --set postgresql.auth.username=appuser \
  --set postgresql.auth.password=AppUserPassword \
  --set postgresql.auth.database=appdb \
  --set backup.s3Bucket=my-db-backups \
  --set backup.s3Region=ap-south-1 \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/pg-backup-irsa \
  --namespace data \
  --create-namespace
```

---

## Values Reference

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| `postgresql.enabled` | Deploy PostgreSQL StatefulSets | bool | `true` | No |
| `postgresql.replicaCount` | Total pods (1 primary + N-1 replicas) | int | `3` | No |
| `postgresql.image.tag` | PostgreSQL + repmgr image tag | string | `16.2.0` | No |
| `postgresql.auth.postgresPassword` | Superuser password | string | `""` | **Yes** |
| `postgresql.auth.username` | Application DB username | string | `""` | No |
| `postgresql.auth.password` | Application DB user password | string | `""` | No |
| `postgresql.auth.database` | Application database name | string | `""` | No |
| `postgresql.auth.existingSecret` | Pre-existing secret with credentials | string | `""` | No |
| `postgresql.primary.persistence.storageClass` | Primary StorageClass | string | `gp3` | No |
| `postgresql.primary.persistence.size` | Primary PVC size | string | `50Gi` | No |
| `postgresql.metrics.enabled` | Deploy postgres_exporter sidecar | bool | `true` | No |
| `postgresql.metrics.serviceMonitor.enabled` | Create ServiceMonitor for Prometheus | bool | `true` | No |
| `pgbouncer.enabled` | Deploy PgBouncer connection pooler | bool | `true` | No |
| `pgbouncer.replicaCount` | PgBouncer pod replicas | int | `2` | No |
| `pgbouncer.poolMode` | Pool mode (`transaction`/`session`/`statement`) | string | `transaction` | No |
| `pgbouncer.maxClientConn` | Max connections from apps to PgBouncer | int | `1000` | No |
| `pgbouncer.defaultPoolSize` | Connections from PgBouncer to PostgreSQL | int | `25` | No |
| `backup.enabled` | Deploy S3 backup CronJob | bool | `true` | No |
| `backup.schedule` | Cron schedule for backups | string | `0 2 * * *` | No |
| `backup.s3Bucket` | S3 bucket name (no `s3://` prefix) | string | `""` | **If backup enabled** |
| `backup.s3Region` | S3 bucket AWS region | string | `""` | **If backup enabled** |
| `backup.retentionDays` | Delete backups older than N days | int | `30` | No |
| `networkPolicy.enabled` | Restrict DB access via NetworkPolicy | bool | `true` | No |
| `networkPolicy.allowNamespaces` | Namespaces allowed to connect | list | `[]` | No |
| `serviceAccount.annotations` | ServiceAccount annotations (use for IRSA) | map | `{}` | No |

---

## Usage Examples

### Example 1 — Allow specific namespaces to connect

```yaml
# values-production.yaml
networkPolicy:
  enabled: true
  allowNamespaces:
    - name: backend
    - name: payment-api
    - name: reporting
```

### Example 2 — Using an existing credentials secret

```bash
# Create the secret manually
kubectl create secret generic pg-credentials \
  --from-literal=postgres-password=SuperSecret \
  --from-literal=password=AppSecret \
  --from-literal=replication-password=ReplSecret \
  --namespace data

helm install postgres akashyadav/postgresql-ha \
  --set postgresql.auth.existingSecret=pg-credentials \
  --set backup.s3Bucket=my-backups \
  --set backup.s3Region=ap-south-1 \
  --namespace data
```

### Example 3 — Scale up storage for large databases

```yaml
postgresql:
  replicaCount: 3
  primary:
    persistence:
      size: 500Gi
    resources:
      requests:
        cpu: 2000m
        memory: 4Gi
      limits:
        cpu: 8000m
        memory: 16Gi
  replica:
    persistence:
      size: 500Gi
```

---

## Connecting Your Application

Always connect via PgBouncer, not directly to PostgreSQL:

```
Host:     postgres-postgresql-ha-pgbouncer.data.svc.cluster.local
Port:     5432
Database: appdb
User:     appuser
```

For read-only queries (reporting, analytics), connect to replicas directly:
```
Host:     postgres-postgresql-ha-replica.data.svc.cluster.local
```

---

## Monitoring Replication Lag

```bash
# Check replication status on primary
kubectl exec -n data postgres-postgresql-ha-primary-0 \
  -- psql -U postgres -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# Check replication lag from replica perspective
kubectl exec -n data postgres-postgresql-ha-replica-0 \
  -- psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_delay;"
```

---

## Backup and Restore Procedure

```bash
# Trigger a manual backup immediately
kubectl create job --from=cronjob/postgres-postgresql-ha-backup \
  manual-backup-$(date +%Y%m%d) -n data

# Watch backup logs
kubectl logs -n data -l app.kubernetes.io/component=backup -f

# Restore from a backup file
kubectl exec -n data postgres-postgresql-ha-primary-0 -- \
  pg_restore --host=localhost --username=postgres \
  --dbname=appdb --verbose /path/to/backup.dump
```

---

## Upgrade Notes

```bash
helm upgrade postgres akashyadav/postgresql-ha \
  -f values-production.yaml \
  --set postgresql.auth.postgresPassword=SuperSecretPassword \
  --namespace data \
  --atomic --timeout 10m
```

**Never change PVC size via Helm** — StatefulSet PVCs are immutable. Resize PVCs directly with `kubectl patch pvc`.

---

## Troubleshooting

**Replica pods stuck in `Init` or `Pending`**
- Replicas stream from the primary using repmgr. If the primary is not ready, replicas wait.
- Check primary logs: `kubectl logs -n data postgres-postgresql-ha-primary-0`
- Ensure the replication password in the secret is consistent between primary and replica.

**PgBouncer returning `FATAL: no more connections allowed`**
- `maxClientConn` is exhausted. Either increase it or reduce application connection pool sizes.
- Check PgBouncer stats: `SHOW POOLS;` via psql connecting to port 5432, database `pgbouncer`.

**Backup job failing with `AccessDenied`**
- IRSA annotation on the ServiceAccount must match a role with S3 write permissions.
- Verify: `kubectl get sa -n data postgres-postgresql-ha -o yaml | grep role-arn`

**`psql: error: connection refused` from PgBouncer**
- PgBouncer cannot reach the PostgreSQL primary. Check the primary service:
  `kubectl get svc -n data postgres-postgresql-ha-primary`
- Confirm the primary pod is running and passing readiness probes.

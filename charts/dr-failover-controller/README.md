# dr-failover-controller

Automated Disaster Recovery health monitoring and Route 53 failover controller for multi-region AWS deployments. Runs as a Kubernetes CronJob that monitors primary region health via HTTP endpoint checks, Aurora replication lag, and ElastiCache availability. Triggers Route 53 DNS failover automatically (if opted in) or with SNS-based manual approval. Implements the active-passive DR pattern with RPO under 3 hours and RTO under 30 minutes.

---

## Architecture

```
Every 5 minutes (CronJob):
┌─────────────────────────────────────────────────────────────┐
│  health-check.sh                                             │
│                                                              │
│  ① HTTP probe → primary endpoint (timeout 10s)              │
│  ② Aurora DescribeDBClusters → replication lag check        │
│  ③ ElastiCache TCP connect → availability check             │
│                                                              │
│  All pass?  → reset failure counter, exit 0                 │
│  Any fail?  → increment counter                             │
│                                                              │
│  Counter ≥ threshold (3)?                                   │
│    → failover-trigger.sh                                    │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  failover-trigger.sh                                         │
│                                                              │
│  autoFailover: false  → Send SNS → Wait for manual exec     │
│  autoFailover: true   → execute-failover.sh immediately     │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  execute-failover.sh                                         │
│                                                              │
│  aws route53 change-resource-record-sets                    │
│  Primary CNAME → DR endpoint (TTL 60s)                      │
│  SNS: "DR FAILOVER COMPLETE"                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| EKS cluster 1.29+ | Controller runs in the primary region cluster |
| IRSA role | `route53:ChangeResourceRecordSets`, `route53:ListResourceRecordSets`, `sns:Publish`, `rds:DescribeDBClusters`, `elasticache:DescribeReplicationGroups` |
| SNS topic | Pre-created in primary region — ARN passed via `controller.failover.sns.topicArn` |
| Route 53 hosted zone | With failover routing policy records pre-configured |
| DR region infrastructure | Aurora read replica, ElastiCache replica, and application cluster must be pre-provisioned in DR region |

---

## Installation

```bash
helm install dr-controller akashyadav/dr-failover-controller \
  --set controller.healthChecks.primary.endpoint=https://api.example.com/health \
  --set controller.failover.route53.hostedZoneId=Z1234567890ABCDE \
  --set controller.failover.route53.primaryRecordName=api.example.com \
  --set controller.failover.route53.drRecordName=api-dr.example.com \
  --set controller.failover.sns.topicArn=arn:aws:sns:ap-south-1:123456789:dr-alerts \
  --set controller.healthChecks.aurora.clusterIdentifier=prod-aurora-cluster \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/dr-controller-role \
  --namespace dr \
  --create-namespace
```

---

## Values Reference

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| `controller.enabled` | Enable the DR controller | bool | `true` | No |
| `controller.replicaCount` | Controller pod replicas | int | `2` | No |
| `controller.schedule` | Health check CronJob schedule | string | `*/5 * * * *` | No |
| `controller.healthChecks.primary.endpoint` | Primary region health endpoint URL | string | `""` | **Yes** |
| `controller.healthChecks.primary.consecutiveFailures` | Failures before failover trigger | int | `3` | No |
| `controller.healthChecks.primary.timeoutSeconds` | HTTP probe timeout | int | `10` | No |
| `controller.healthChecks.aurora.checkEnabled` | Include Aurora replication lag | bool | `true` | No |
| `controller.healthChecks.aurora.clusterIdentifier` | Aurora cluster identifier | string | `""` | If Aurora check enabled |
| `controller.healthChecks.elasticache.checkEnabled` | Include ElastiCache availability | bool | `true` | No |
| `controller.healthChecks.elasticache.primaryEndpoint` | ElastiCache endpoint (host:port) | string | `""` | If EC check enabled |
| `controller.failover.route53.hostedZoneId` | Route 53 hosted zone ID | string | `""` | **Yes** |
| `controller.failover.route53.primaryRecordName` | DNS record for primary region | string | `""` | **Yes** |
| `controller.failover.route53.drRecordName` | DNS record for DR region | string | `""` | **Yes** |
| `controller.failover.route53.autoFailover` | Trigger failover automatically | bool | `false` | No |
| `controller.failover.route53.requireManualApproval` | Require manual exec for failover | bool | `true` | No |
| `controller.failover.sns.topicArn` | SNS topic ARN for DR alerts | string | `""` | **Yes** |
| `controller.aws.region` | Primary AWS region | string | `ap-south-1` | No |
| `controller.aws.drRegion` | DR AWS region | string | `ap-south-2` | No |
| `serviceAccount.annotations` | IRSA role ARN annotation | map | `{}` | **Yes** |
| `metrics.enabled` | Expose Prometheus metrics | bool | `true` | No |
| `metrics.serviceMonitor.enabled` | Create ServiceMonitor | bool | `true` | No |
| `grafana.dashboard.enabled` | Deploy Grafana dashboard ConfigMap | bool | `true` | No |

---

## Testing Failover Without Triggering It

```bash
# 1. Trigger an immediate health check job
kubectl create job --from=cronjob/dr-controller-dr-failover-controller-healthcheck \
  test-check-$(date +%s) -n dr

# 2. Watch the check run
kubectl logs -n dr -l app.kubernetes.io/component=healthcheck -f

# 3. Exec into the controller to dry-run the failover script (read-only inspection)
kubectl exec -n dr \
  $(kubectl get pod -n dr -l app.kubernetes.io/name=dr-failover-controller -o name | head -1) \
  -- /bin/sh -c "echo 'DRY RUN — would call: aws route53 change-resource-record-sets --hosted-zone-id ${ROUTE53_HOSTED_ZONE_ID}'"
```

---

## Manual Failover Procedure

When `autoFailover: false` and an SNS alert is received:

```bash
# 1. Verify the alert and confirm primary region is genuinely degraded
curl -sS https://api.example.com/health

# 2. Confirm DR region infrastructure is ready
# (Aurora replica, ElastiCache replica, application pods in DR cluster)

# 3. Execute the failover
kubectl exec -n dr \
  $(kubectl get pod -n dr -l app.kubernetes.io/name=dr-failover-controller -o name | head -1) \
  -- /scripts/execute-failover.sh

# 4. Verify Route 53 update propagated (TTL is 60s)
watch -n 5 "dig +short api.example.com"

# 5. Confirm application traffic is routing to DR region
curl -sS https://api.example.com/health
```

---

## Failing Back to Primary

After the primary region is restored:

```bash
# 1. Verify primary region is fully healthy
curl -sS https://api.primary.example.com/health

# 2. Verify Aurora replica in primary is caught up
aws rds describe-db-clusters --db-cluster-identifier prod-aurora \
  --query 'DBClusters[0].Status'

# 3. Update Route 53 to point back to primary
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABCDE \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "api.primary.example.com"}]
      }
    }]
  }'

# 4. Reset the consecutive failure counter in the controller
kubectl exec -n dr \
  $(kubectl get pod -n dr -l app.kubernetes.io/name=dr-failover-controller -o name | head -1) \
  -- rm -f /tmp/consecutive-failures
```

---

## Upgrade Notes

```bash
helm upgrade dr-controller akashyadav/dr-failover-controller \
  -f values-dr.yaml \
  --namespace dr \
  --atomic --timeout 5m
```

---

## Troubleshooting

**Health check CronJob not running**
- Check CronJob status: `kubectl get cronjob -n dr`
- Check for missed schedules: `kubectl describe cronjob -n dr dr-controller-dr-failover-controller-healthcheck`
- Ensure the kube-controller-manager is healthy (CronJob scheduling requires it).

**Route 53 update failing with `AccessDenied`**
- IRSA annotation is missing or the role lacks `route53:ChangeResourceRecordSets`.
- Verify: `kubectl get sa -n dr dr-controller-dr-failover-controller -o yaml | grep role-arn`
- Test permissions: `aws sts get-caller-identity` from inside the controller pod.

**SNS notifications not being received**
- Confirm the topic ARN is correct and the IRSA role has `sns:Publish` on that topic.
- Check the controller logs: `kubectl logs -n dr -l app.kubernetes.io/name=dr-failover-controller`

**False-positive failover being triggered**
- Increase `consecutiveFailures` (e.g. to 5) to require more failures before triggering.
- Check for transient network issues between the cluster and the health endpoint.
- Review the health check logs to see which specific check is failing.

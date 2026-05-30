# microservice

A production-ready, reusable Helm chart for deploying any containerized microservice on Amazon EKS. Ships with HPA, PodDisruptionBudget, IRSA-ready ServiceAccount, NetworkPolicy, Secrets Store CSI support, and topology spread constraints to guarantee high availability across Availability Zones. This chart covers 90% of real EKS deployment needs without modification.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Kubernetes | 1.29+ | EKS recommended |
| Helm | 3.14+ | |
| AWS ALB Ingress Controller | 2.x | Required only if `ingress.enabled: true` |
| Secrets Store CSI Driver | 1.x | Required only if `secretsStoreCsi.enabled: true` |
| Karpenter | 0.34+ | Recommended for node autoscaling |
| metrics-server | 0.6+ | Required for HPA to function |

---

## Installation

```bash
# Add the repo
helm repo add akashyadav \
  https://akashyadavdevopsproject.github.io/helm-charts-kubernetes
helm repo update

# Install with minimum required values
helm install my-service akashyadav/microservice \
  --set image.repository=123456789.dkr.ecr.ap-south-1.amazonaws.com/my-service \
  --set image.tag=v1.0.0 \
  --namespace production \
  --create-namespace
```

---

## Values Reference

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| `replicaCount` | Minimum pod replicas (HPA scales above this) | int | `2` | No |
| `image.repository` | Container image URI (ECR URI recommended) | string | `""` | **Yes** |
| `image.tag` | Image tag — use commit SHA in production, never `latest` | string | `"latest"` | **Yes** |
| `image.pullPolicy` | Image pull policy (`IfNotPresent` / `Always`) | string | `IfNotPresent` | No |
| `imagePullSecrets` | List of pull secret names for private registries | list | `[]` | No |
| `nameOverride` | Override chart name portion of resource names | string | `""` | No |
| `fullnameOverride` | Override full resource name | string | `""` | No |
| `serviceAccount.create` | Create a new ServiceAccount | bool | `true` | No |
| `serviceAccount.annotations` | Annotations on the ServiceAccount (use for IRSA) | map | `{}` | No |
| `serviceAccount.name` | ServiceAccount name (auto-generated if empty) | string | `""` | No |
| `podAnnotations` | Annotations on pods (Prometheus scrape config by default) | map | see values.yaml | No |
| `podSecurityContext.runAsNonRoot` | Reject pods running as root | bool | `true` | No |
| `podSecurityContext.runAsUser` | UID to run container process | int | `1000` | No |
| `podSecurityContext.fsGroup` | GID for mounted volume ownership | int | `2000` | No |
| `securityContext.allowPrivilegeEscalation` | Block privilege escalation | bool | `false` | No |
| `securityContext.readOnlyRootFilesystem` | Read-only root filesystem | bool | `true` | No |
| `securityContext.capabilities.drop` | Linux capabilities to drop | list | `[ALL]` | No |
| `service.type` | Kubernetes service type | string | `ClusterIP` | No |
| `service.port` | Service port | int | `80` | No |
| `service.targetPort` | Container port | int | `8080` | No |
| `ingress.enabled` | Create ALB Ingress resource | bool | `false` | No |
| `ingress.className` | Ingress class name | string | `alb` | No |
| `ingress.annotations` | ALB Ingress Controller annotations | map | see values.yaml | No |
| `ingress.hosts` | List of host/path rules | list | `[{host: "", paths: [{path: /, pathType: Prefix}]}]` | No |
| `ingress.tls` | TLS configuration | list | `[]` | No |
| `resources.requests.cpu` | Guaranteed CPU | string | `100m` | No |
| `resources.requests.memory` | Guaranteed memory | string | `128Mi` | No |
| `resources.limits.cpu` | Max CPU before throttling | string | `500m` | No |
| `resources.limits.memory` | Max memory before OOMKill | string | `512Mi` | No |
| `autoscaling.enabled` | Deploy HorizontalPodAutoscaler | bool | `true` | No |
| `autoscaling.minReplicas` | HPA minimum replicas | int | `2` | No |
| `autoscaling.maxReplicas` | HPA maximum replicas | int | `10` | No |
| `autoscaling.targetCPUUtilizationPercentage` | CPU scale-up threshold | int | `70` | No |
| `autoscaling.targetMemoryUtilizationPercentage` | Memory scale-up threshold | int | `80` | No |
| `podDisruptionBudget.enabled` | Deploy PodDisruptionBudget | bool | `true` | No |
| `podDisruptionBudget.minAvailable` | Minimum pods available during disruptions | int | `1` | No |
| `livenessProbe.httpGet.path` | Liveness probe HTTP path | string | `/health` | No |
| `livenessProbe.httpGet.port` | Liveness probe port | int | `8080` | No |
| `livenessProbe.initialDelaySeconds` | Delay before first liveness probe | int | `30` | No |
| `livenessProbe.periodSeconds` | Liveness probe interval | int | `10` | No |
| `livenessProbe.failureThreshold` | Restarts after N consecutive failures | int | `3` | No |
| `readinessProbe.httpGet.path` | Readiness probe HTTP path | string | `/ready` | No |
| `readinessProbe.httpGet.port` | Readiness probe port | int | `8080` | No |
| `readinessProbe.initialDelaySeconds` | Delay before first readiness probe | int | `10` | No |
| `startupProbe.httpGet.path` | Startup probe HTTP path | string | `/health` | No |
| `startupProbe.failureThreshold` | Max startup failures (30 × 10s = 5 min) | int | `30` | No |
| `networkPolicy.enabled` | Deploy NetworkPolicy (deny-all except allowed) | bool | `true` | No |
| `networkPolicy.ingress` | Allowed ingress sources for NetworkPolicy | list | ingress-nginx namespace | No |
| `secretsStoreCsi.enabled` | Mount AWS Secrets Manager secrets via CSI | bool | `false` | No |
| `secretsStoreCsi.secretProviderClass` | Name of SecretProviderClass resource | string | `""` | If CSI enabled |
| `topologySpreadConstraints` | Pod spread across AZs and nodes | list | see values.yaml | No |
| `affinity` | Pod affinity/anti-affinity rules | map | soft anti-affinity | No |
| `lifecycle.preStop` | preStop hook (default: sleep 5 for drain) | map | see values.yaml | No |
| `terminationGracePeriodSeconds` | Grace period before SIGKILL | int | `30` | No |
| `env` | Extra environment variables (name/value pairs) | list | `[]` | No |
| `envFrom` | Inject ConfigMap or Secret as env vars | list | `[]` | No |
| `nodeSelector` | Node label selectors | map | `{}` | No |
| `tolerations` | Node taint tolerations | list | `[]` | No |

---

## Usage Examples

### Example 1 — Basic Node.js microservice

```bash
helm install payments-api akashyadav/microservice \
  --set image.repository=123456789.dkr.ecr.ap-south-1.amazonaws.com/payments-api \
  --set image.tag=abc1234 \
  --set replicaCount=3 \
  --set resources.requests.cpu=200m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.cpu=1000m \
  --set resources.limits.memory=1Gi \
  --namespace production \
  --create-namespace
```

### Example 2 — Java Spring Boot with IRSA + AWS Secrets Manager

```yaml
# values-java-prod.yaml
image:
  repository: 123456789.dkr.ecr.ap-south-1.amazonaws.com/ledger-service
  tag: v2.1.0
  pullPolicy: IfNotPresent

replicaCount: 3

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ledger-service-role

livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 60

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 30

startupProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  failureThreshold: 30

secretsStoreCsi:
  enabled: true
  secretProviderClass: ledger-service-secrets

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 15
  targetCPUUtilizationPercentage: 65
```

```bash
helm install ledger-service akashyadav/microservice \
  -f values-java-prod.yaml \
  --namespace production
```

### Example 3 — High-traffic payment gateway with ALB + custom NetworkPolicy

```yaml
# values-payment-gateway.yaml
image:
  repository: 123456789.dkr.ecr.ap-south-1.amazonaws.com/payment-gateway
  tag: v3.4.1

replicaCount: 5

ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-south-1:123456789:certificate/abc-123
  hosts:
    - host: pay.example.com
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

autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 50
  targetCPUUtilizationPercentage: 60

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

```bash
helm install payment-gateway akashyadav/microservice \
  -f values-payment-gateway.yaml \
  --namespace payment-processing
```

---

## Upgrade Notes

```bash
# Preview changes before upgrading
helm diff upgrade my-service akashyadav/microservice \
  -f values-prod.yaml --namespace production

# Upgrade
helm upgrade my-service akashyadav/microservice \
  -f values-prod.yaml --namespace production --atomic --timeout 5m

# Rollback if needed
helm rollback my-service 0 --namespace production
```

---

## Troubleshooting

**Pods stuck in `Pending` state**
- Check `kubectl describe pod` for `Insufficient cpu` or `Insufficient memory` — scale up node capacity or reduce resource requests.
- Check topology spread constraints — if only one AZ has nodes, `DoNotSchedule` blocks pending pods. Change to `ScheduleAnyway` for dev environments.

**`OOMKilled` restarts**
- Memory limit is too low. Observe actual memory usage: `kubectl top pod -n NAMESPACE` and increase `resources.limits.memory`.

**`readinessProbe` failing — pod never becomes Ready**
- Confirm the app responds with HTTP 200 on `/ready`. For Spring Boot, use `/actuator/health/readiness`. Check container logs: `kubectl logs -n NAMESPACE POD_NAME`.

**`CrashLoopBackOff` immediately after deploy**
- `readOnlyRootFilesystem: true` may prevent app from writing temporary files. Add an `emptyDir` volume mount for `/tmp` or the required write path.

**HPA shows `<unknown>` for metrics**
- `metrics-server` is not installed or not running. Install it: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`

**NetworkPolicy blocking traffic unexpectedly**
- Use `kubectl exec` to test connectivity and check NetworkPolicy rules with `kubectl get networkpolicy -n NAMESPACE -o yaml`.

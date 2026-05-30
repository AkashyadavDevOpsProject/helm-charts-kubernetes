# devsecops-pipeline

GitLab CI/CD runner deployment on Amazon EKS with integrated security tooling. Deploys GitLab Kubernetes executor runners alongside Trivy image scanning configuration, OPA Gatekeeper Rego policies, and optional HashiCorp Vault agent injection. This is the DevSecOps stack used in SOC 2 Type II compliant FinTech production environments — ephemeral build pods, no persistent runner state, IRSA-based AWS auth.

---

## What Each Component Does

| Component | Purpose |
|-----------|---------|
| **GitLab Runner** | Kubernetes executor — each CI job runs in a fresh ephemeral pod. No persistent build state. |
| **Trivy** | Container image vulnerability scanner. Fails the pipeline on HIGH/CRITICAL CVEs with available fixes. |
| **OPA Policies** | Rego policy definitions stored as a ConfigMap. Apply via OPA Gatekeeper ConstraintTemplates to enforce security posture across the cluster. |
| **Vault Agent** | Optional sidecar that authenticates to HashiCorp Vault via Kubernetes auth and injects secrets into the runner pod filesystem. |

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| EKS cluster 1.29+ | |
| GitLab instance | Self-hosted or gitlab.com |
| Runner registration token | Settings → CI/CD → Runners |
| OPA Gatekeeper (optional) | Required to enforce Rego policies — install separately |
| HashiCorp Vault (optional) | Required only if `vault.agent.enabled: true` |
| IRSA role (optional) | For AWS API access from build jobs |

---

## Installation

```bash
# Minimum required — runner only
helm install devsecops akashyadav/devsecops-pipeline \
  --set gitlab.runner.gitlabUrl=https://gitlab.example.com \
  --set gitlab.runner.runnerToken=glrt-xxxxxxxxxxxxxxxxxxxx \
  --namespace devops \
  --create-namespace

# With Vault agent enabled
helm install devsecops akashyadav/devsecops-pipeline \
  --set gitlab.runner.gitlabUrl=https://gitlab.example.com \
  --set gitlab.runner.runnerToken=glrt-xxxxxxxxxxxxxxxxxxxx \
  --set vault.agent.enabled=true \
  --set vault.agent.address=https://vault.internal.example.com:8200 \
  --set vault.agent.role=gitlab-runner \
  --namespace devops \
  --create-namespace
```

---

## Values Reference

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| `gitlab.runner.enabled` | Deploy GitLab Runner | bool | `true` | No |
| `gitlab.runner.replicas` | Number of runner manager pods | int | `3` | No |
| `gitlab.runner.gitlabUrl` | GitLab instance URL | string | `""` | **Yes** |
| `gitlab.runner.runnerToken` | Runner registration token | string | `""` | **Yes** (or `existingSecret`) |
| `gitlab.runner.existingSecret` | Pre-existing secret with `runner-token` key | string | `""` | No |
| `gitlab.runner.concurrent` | Max concurrent jobs per runner pod | int | `10` | No |
| `gitlab.runner.image.tag` | GitLab runner image tag | string | `alpine-v16.9.0` | No |
| `gitlab.runner.resources.limits.cpu` | Runner pod CPU limit | string | `1000m` | No |
| `gitlab.runner.resources.limits.memory` | Runner pod memory limit | string | `1Gi` | No |
| `trivy.enabled` | Enable Trivy scanner config | bool | `true` | No |
| `trivy.severity` | Severities that fail the pipeline | string | `HIGH,CRITICAL` | No |
| `trivy.exitCode` | Exit code on findings (`1` = fail pipeline) | int | `1` | No |
| `trivy.ignoreUnfixed` | Skip CVEs without available fix | bool | `true` | No |
| `vault.agent.enabled` | Inject Vault agent sidecar | bool | `false` | No |
| `vault.agent.address` | Vault server URL | string | `""` | If Vault enabled |
| `vault.agent.role` | Vault Kubernetes auth role | string | `""` | If Vault enabled |
| `vault.agent.authPath` | Vault auth mount path | string | `kubernetes` | No |
| `opa.enabled` | Deploy OPA Rego policies ConfigMap | bool | `true` | No |
| `opa.policies.requireNonRootUser` | Block root containers | bool | `true` | No |
| `opa.policies.requireReadOnlyRootFS` | Block writable root filesystem | bool | `true` | No |
| `opa.policies.blockLatestTag` | Block `:latest` image tags | bool | `true` | No |
| `opa.policies.requireResourceLimits` | Block pods without CPU/memory limits | bool | `true` | No |
| `opa.policies.requireTrustedRegistry` | Block non-approved registries | bool | `false` | No |
| `opa.policies.trustedRegistries` | List of allowed registry prefixes | list | `[]` | If registry policy enabled |
| `serviceAccount.annotations` | ServiceAccount annotations (use for IRSA) | map | `{}` | No |
| `rbac.create` | Create ClusterRole and RoleBinding | bool | `true` | No |

---

## Usage Examples

### Example 1 — High-throughput runner fleet

```yaml
# values-runner-fleet.yaml
gitlab:
  runner:
    replicas: 10
    concurrent: 20
    resources:
      limits:
        cpu: 2000m
        memory: 2Gi
```

### Example 2 — Using an existing secret for the runner token

```bash
# Create the secret manually first
kubectl create secret generic gitlab-runner-secret \
  --from-literal=runner-token=glrt-xxxxxxxxxxxx \
  --namespace devops

# Deploy chart referencing the existing secret
helm install devsecops akashyadav/devsecops-pipeline \
  --set gitlab.runner.gitlabUrl=https://gitlab.example.com \
  --set gitlab.runner.existingSecret=gitlab-runner-secret \
  --namespace devops
```

### Example 3 — Trust only ECR images

```yaml
opa:
  enabled: true
  policies:
    requireTrustedRegistry: true
    trustedRegistries:
      - "123456789.dkr.ecr.ap-south-1.amazonaws.com"
      - "registry.gitlab.com/mygroup"
```

---

## Verifying Runner Registration

```bash
# Check pod status
kubectl get pods -n devops -l app.kubernetes.io/name=devsecops-pipeline

# Check runner logs for registration confirmation
kubectl logs -n devops -l app.kubernetes.io/name=devsecops-pipeline --tail=50

# Verify in GitLab UI
# → Your project → Settings → CI/CD → Runners → Assigned runners
```

---

## OPA Policy Enforcement

The Rego policies in this chart are stored as a ConfigMap. To enforce them with OPA Gatekeeper:

1. Install OPA Gatekeeper: `helm install gatekeeper opa/gatekeeper --namespace gatekeeper-system`
2. Create a `ConstraintTemplate` referencing each Rego policy
3. Create a `Constraint` targeting the namespaces to enforce

```bash
# View the generated Rego policies
kubectl get configmap devsecops-opa-policies -n devops -o yaml
```

---

## Upgrade Notes

```bash
helm upgrade devsecops akashyadav/devsecops-pipeline \
  --set gitlab.runner.gitlabUrl=https://gitlab.example.com \
  --set gitlab.runner.existingSecret=gitlab-runner-secret \
  --namespace devops \
  --atomic --timeout 5m
```

---

## Troubleshooting

**Runner pods are running but not visible in GitLab**
- Check runner logs: `kubectl logs -n devops -l app.kubernetes.io/name=devsecops-pipeline`
- Verify `gitlab.runner.gitlabUrl` is reachable from inside the cluster: `kubectl exec -n devops POD -- wget -qO- GITLAB_URL/-/health`
- Confirm the runner token is correct — a wrong token gives a 403 during registration.

**CI jobs fail with `pods "..." is forbidden`**
- The runner ServiceAccount lacks permission. Check the RoleBinding: `kubectl get rolebinding -n devops`
- Ensure `rbac.create: true` or apply the ClusterRole manually.

**Vault injection not working**
- Vault Kubernetes auth must be enabled: `vault auth enable kubernetes`
- The role must exist: `vault read auth/kubernetes/role/ROLE_NAME`
- Check Vault agent sidecar logs: `kubectl logs -n devops POD -c vault-agent`

**OPA blocking valid pods unexpectedly**
- Read the denial reason from the event: `kubectl get events -n NAMESPACE --field-selector reason=FailedCreate`
- Test a policy dry-run by setting `opa.policies.requireTrustedRegistry: false` temporarily to isolate the failing check.

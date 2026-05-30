# eks-autoscaler

Karpenter NodePools, EC2NodeClass, HPA defaults, and optional VPA for Amazon EKS. Deploys On-Demand (Graviton3), Spot (multi-family), and GPU (optional) node pools with IMDSv2 enforcement, gp3 encrypted EBS, AL2023 AMI, and cost consolidation policies. This is the autoscaling stack used across production EKS clusters running FinTech payment workloads.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| EKS cluster 1.29+ | |
| Karpenter 0.34+ | Installed in `karpenter` namespace via its own Helm chart |
| Karpenter CRDs | `NodePool`, `EC2NodeClass`, `NodeClaim` CRDs must be installed |
| SQS queue | For Spot interruption handling — name passed via `karpenter.interruptionQueue` |
| IAM role for nodes | EC2 instance profile with `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore` |
| Subnet/SG tags | Subnets and security groups must have `karpenter.sh/discovery: CLUSTER_NAME` tag |

### Verify prerequisites

```bash
# Karpenter is running
kubectl get pods -n karpenter

# CRDs are installed
kubectl get crd nodepools.karpenter.sh ec2nodeclasses.karpenter.k8s.aws

# Subnets are tagged (replace CLUSTER_NAME)
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=CLUSTER_NAME" \
  --query 'Subnets[*].SubnetId'
```

---

## Installation

```bash
helm install autoscaler akashyadav/eks-autoscaler \
  --set karpenter.clusterName=my-production-cluster \
  --set karpenter.clusterEndpoint=https://XXXXXXXX.gr7.ap-south-1.eks.amazonaws.com \
  --set karpenter.interruptionQueue=my-production-cluster-karpenter-interruption \
  --set ec2NodeClass.role=KarpenterNodeRole-my-production-cluster \
  --set "ec2NodeClass.subnetSelectorTerms[0].tags.karpenter\.sh/discovery=my-production-cluster" \
  --set "ec2NodeClass.securityGroupSelectorTerms[0].tags.karpenter\.sh/discovery=my-production-cluster" \
  --set ec2NodeClass.tags.Environment=production \
  --set ec2NodeClass.tags.CostCenter=platform \
  --namespace karpenter \
  --create-namespace
```

---

## Values Reference

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| `karpenter.clusterName` | EKS cluster name | string | `""` | **Yes** |
| `karpenter.clusterEndpoint` | EKS API server endpoint URL | string | `""` | **Yes** |
| `karpenter.interruptionQueue` | SQS queue name for Spot interruption events | string | `""` | **Yes** |
| `karpenter.nodePools.general.enabled` | Deploy On-Demand general NodePool | bool | `true` | No |
| `karpenter.nodePools.general.instanceTypes` | EC2 instance types for general pool | list | m7g/m6g | No |
| `karpenter.nodePools.general.capacityType` | `on-demand` or `spot` | list | `[on-demand]` | No |
| `karpenter.nodePools.general.amiFamily` | AMI family (`AL2023` required for EKS 1.29+) | string | `AL2023` | No |
| `karpenter.nodePools.general.volumeSize` | Root EBS volume size | string | `50Gi` | No |
| `karpenter.nodePools.general.encrypted` | Encrypt EBS volumes | bool | `true` | No |
| `karpenter.nodePools.general.imdsHopLimit` | IMDSv2 hop limit (must be 2 for EKS pods) | int | `2` | No |
| `karpenter.nodePools.general.limits.cpu` | Max vCPU for general pool | string | `"100"` | No |
| `karpenter.nodePools.general.limits.memory` | Max memory for general pool | string | `400Gi` | No |
| `karpenter.nodePools.general.disruption.consolidationPolicy` | Consolidation policy | string | `WhenUnderutilized` | No |
| `karpenter.nodePools.spot.enabled` | Deploy Spot NodePool | bool | `true` | No |
| `karpenter.nodePools.spot.instanceTypes` | EC2 instance types for Spot pool | list | m7g/m6g/c7g/c6g/r7g/r6g | No |
| `karpenter.nodePools.spot.limits.cpu` | Max vCPU for Spot pool | string | `"200"` | No |
| `karpenter.nodePools.gpu.enabled` | Deploy GPU NodePool | bool | `false` | No |
| `karpenter.nodePools.gpu.instanceTypes` | GPU instance types | list | g4dn/g5 | No |
| `ec2NodeClass.amiSelectorTerms` | AMI selection terms | list | `al2023@latest` | No |
| `ec2NodeClass.role` | EC2 node IAM role name (not ARN) | string | `""` | **Yes** |
| `ec2NodeClass.subnetSelectorTerms` | Subnet discovery tags | list | — | **Yes** |
| `ec2NodeClass.securityGroupSelectorTerms` | Security group discovery tags | list | — | **Yes** |
| `ec2NodeClass.tags` | EC2 resource tags | map | `{ManagedBy: karpenter}` | No |
| `vpa.enabled` | Deploy VPA resource | bool | `false` | No |
| `vpa.updateMode` | VPA update mode (`Off`/`Initial`/`Auto`) | string | `Off` | No |

---

## Usage Examples

### Example 1 — Production cluster with Spot preference

```bash
helm install autoscaler akashyadav/eks-autoscaler \
  --set karpenter.clusterName=prod-eks \
  --set karpenter.clusterEndpoint=https://ABC123.gr7.ap-south-1.eks.amazonaws.com \
  --set karpenter.interruptionQueue=prod-eks-karpenter-interruption \
  --set ec2NodeClass.role=KarpenterNodeRole-prod-eks \
  --set "ec2NodeClass.subnetSelectorTerms[0].tags.karpenter\.sh/discovery=prod-eks" \
  --set "ec2NodeClass.securityGroupSelectorTerms[0].tags.karpenter\.sh/discovery=prod-eks" \
  --namespace karpenter
```

### Example 2 — Enable GPU pool for ML workloads

```yaml
# values-gpu.yaml
karpenter:
  clusterName: ml-cluster
  nodePools:
    gpu:
      enabled: true
      instanceTypes:
        - g5.xlarge
        - g5.2xlarge
        - g4dn.xlarge
      limits:
        cpu: "50"
        memory: 400Gi
```

To schedule on GPU nodes, pods must add:
```yaml
tolerations:
  - key: nvidia.com/gpu
    value: "true"
    effect: NoSchedule
resources:
  limits:
    nvidia.com/gpu: 1
```

### Example 3 — Spot-only workloads (batch jobs)

Add this toleration to batch job pods to land on Spot:
```yaml
tolerations:
  - key: karpenter.sh/capacity-type
    value: spot
    effect: NoSchedule
nodeSelector:
  karpenter.sh/capacity-type: spot
```

---

## Spot vs On-Demand Decision Guide

| Workload | Recommended Pool | Reason |
|----------|-----------------|--------|
| API servers / payment processing | On-Demand | Cannot tolerate interruption |
| Stateful services (DBs, queues) | On-Demand | Data loss risk on Spot |
| Batch jobs / async workers | Spot | Tolerant of interruption, 60-90% cheaper |
| CI/CD build runners | Spot | Short-lived, interruptible |
| ML training (checkpoint-enabled) | Spot | Cost savings if checkpointing implemented |
| kube-system / Karpenter itself | On-Demand | System workload, must be stable |

---

## Upgrade Notes

```bash
# Karpenter CRDs must be upgraded separately before upgrading this chart
# See: https://karpenter.sh/docs/upgrading/upgrade-guide/

helm upgrade autoscaler akashyadav/eks-autoscaler \
  -f values-prod.yaml \
  --namespace karpenter \
  --atomic --timeout 5m
```

---

## Troubleshooting

**Nodes not provisioning — pods stuck in `Pending`**
- Check Karpenter logs: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f`
- Verify subnets have the `karpenter.sh/discovery` tag matching your cluster name.
- Confirm the EC2 instance role exists: `aws iam get-role --role-name KarpenterNodeRole-CLUSTER`
- Check NodePool status: `kubectl get nodepool -o yaml`

**IMDSv2 errors in pod logs (`EC2 metadata service is unavailable`)**
- `imdsHopLimit` must be `2`. AL2023 AMIs default to hop limit 1, which blocks pods.
- Confirm: `kubectl get ec2nodeclass -o jsonpath='{.items[0].spec.metadataOptions}'`

**Spot nodes not launching despite Spot pool being enabled**
- Pods must have the `karpenter.sh/capacity-type: spot` toleration to land on Spot nodes.
- Spot capacity may be unavailable for the selected instance types — add more families.

**Consolidation not removing underutilized nodes**
- Check if pods have PodDisruptionBudgets that are blocking eviction: `kubectl get pdb -A`
- Check if pods have `do-not-disrupt` annotation: `kubectl get pod -A -o json | jq '.items[] | select(.metadata.annotations["karpenter.sh/do-not-disrupt"])'`
- `WhenUnderutilized` only fires when a node's pod CPU/memory requests are below threshold.

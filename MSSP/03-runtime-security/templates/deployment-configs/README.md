# Deployment Configurations

> Helm values for different environments and cloud providers.

---

## Available Configurations

| Configuration | Use Case | Cloud | Features |
|--------------|----------|-------|----------|
| `aws-eks.yaml` | Production on AWS EKS | AWS | Falco, CloudWatch, S3 snapshots |
| `azure-aks.yaml` | Production on Azure AKS | Azure | Falco, Azure Monitor, Blob snapshots |
| `gcp-gke.yaml` | Production on Google GKE | GCP | Falco, Cloud Logging, GCS snapshots |
| `on-prem.yaml` | On-premises K8s | Any | Falco, local storage, MinIO |
| `minimal.yaml` | Development/testing | Any | Falco only, no cloud integrations |
| `full-featured.yaml` | Maximum coverage | Any | All watchers + responders enabled |

---

## Quick Start

### 1. Copy the config you need

```bash
cp 03-templates/deployment-configs/aws-eks.yaml my-values.yaml
```

### 2. Edit with your settings

```bash
# Required changes:
# - Slack webhook URL
# - AWS region
# - S3 bucket name
# - JADE endpoint (if separate)

vim my-values.yaml
```

### 3. Install

```bash
helm install jsa-infrasec gp-copilot/jsa-infrasec \
  --namespace gp-security \
  --create-namespace \
  -f my-values.yaml
```

---

## Configuration Details

### AWS EKS (aws-eks.yaml)

**Features:**
- Falco with AWS-specific rules
- CloudWatch log shipping
- S3 snapshot storage
- IAM watcher (monitors role/policy changes)
- S3 watcher (monitors bucket policies)
- EC2 watcher (monitors security groups)
- VPC watcher (monitors network changes)

**Prerequisites:**
- IAM role with permissions:
  - `s3:PutObject` (for snapshots)
  - `iam:List*`, `iam:Get*` (for IAM watcher)
  - `ec2:Describe*` (for EC2/VPC watchers)
  - `logs:PutLogEvents` (for CloudWatch)

**Customization:**
```yaml
cloud:
  aws:
    enabled: true
    region: us-east-1  # Change to your region
    accountId: "123456789012"  # Your AWS account ID
    iamRole: "arn:aws:iam::123456789012:role/jsa-infrasec"

responders:
  snapshot:
    storage: "s3://my-company-jsa-snapshots/"  # Your S3 bucket
```

---

### Azure AKS (azure-aks.yaml)

**Features:**
- Falco with Azure-specific rules
- Azure Monitor integration
- Azure Blob snapshot storage
- Azure RBAC watcher
- Storage Account watcher
- Network Security Group watcher

**Prerequisites:**
- Managed identity with permissions:
  - `Storage Blob Data Contributor` (for snapshots)
  - `Monitoring Contributor` (for Azure Monitor)
  - `Reader` (for resource monitoring)

**Customization:**
```yaml
cloud:
  azure:
    enabled: true
    subscriptionId: "abc-123-def-456"
    resourceGroup: "my-k8s-rg"
    tenantId: "xyz-789-ghi-012"

responders:
  snapshot:
    storage: "azblob://mystorageaccount/jsa-snapshots"
```

---

### GCP GKE (gcp-gke.yaml)

**Features:**
- Falco with GCP-specific rules
- Cloud Logging integration
- GCS snapshot storage
- IAM watcher
- GCS bucket watcher
- VPC watcher

**Prerequisites:**
- Service account with roles:
  - `storage.objectCreator` (for snapshots)
  - `logging.logWriter` (for Cloud Logging)
  - `compute.viewer` (for resource monitoring)

**Customization:**
```yaml
cloud:
  gcp:
    enabled: true
    projectId: "my-gcp-project"
    region: "us-central1"
    serviceAccount: "jsa-infrasec@my-project.iam.gserviceaccount.com"

responders:
  snapshot:
    storage: "gs://my-company-jsa-snapshots/"
```

---

### On-Premises (on-prem.yaml)

**Features:**
- Falco only (no cloud watchers)
- Local or MinIO snapshot storage
- Kubernetes-native features only
- Self-contained (no external dependencies)

**Prerequisites:**
- PersistentVolumeClaim or MinIO

**Customization:**
```yaml
responders:
  snapshot:
    storage: "pvc://jsa-snapshots"  # Use PVC
    # OR
    storage: "s3://minio.local:9000/jsa-snapshots"  # Use MinIO
```

---

### Minimal (minimal.yaml)

**Features:**
- Falco watcher only
- No auto-fix (logging only)
- No cloud integrations
- Lightweight resource usage

**Use case:** Dev/test environments, proof of concept

**Resource usage:**
- CPU: 100m
- Memory: 256Mi

---

### Full-Featured (full-featured.yaml)

**Features:**
- All 20 watchers enabled
- All 16 responders enabled
- JADE integration
- Full MITRE ATT&CK enrichment
- All cloud providers (configure as needed)

**Use case:** Maximum security coverage, enterprise production

**Resource usage:**
- CPU: 1000m
- Memory: 2Gi

---

## Common Customizations

### Change Auto-Fix Rank Ceiling

```yaml
responders:
  autoFix:
    enabled: true
    maxRank: "D"  # Options: E, D, C
    # E = most conservative (metadata only)
    # D = safe automated fixes
    # C = requires JADE approval
```

### Add Slack Channels

```yaml
alerts:
  slack:
    webhook: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    channels:
      critical: "#security-critical"
      high: "#security-alerts"
      medium: "#security-log"
      low: "#security-verbose"
```

### Enable/Disable Watchers

```yaml
watchers:
  falco:
    enabled: true
  kubernetes:
    events: true
    audit: true
    drift: true
    admission: false  # Disable if not needed
  cloud:
    aws:
      enabled: true
      iam: true
      s3: true
      ec2: false  # Disable EC2 watcher
      vpc: false  # Disable VPC watcher
```

### Adjust Resource Limits

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 4Gi
```

### Configure Snapshot Retention

```yaml
responders:
  snapshot:
    enabled: true
    retention:
      days: 30  # Keep snapshots for 30 days
      maxCount: 1000  # Or max 1000 snapshots
```

---

## Validation

After deployment, validate with:

```bash
# Check pods
kubectl get pods -n gp-security

# Check metrics
kubectl port-forward -n gp-security svc/jsa-infrasec 9100:9100
curl http://localhost:9100/metrics | grep jsa_infrasec_watchers_active

# Check Falco integration
kubectl logs -n gp-security deploy/jsa-infrasec --tail=100 | grep falco

# Generate test alert
kubectl exec -n falco daemonset/falco -- \
  falco-event-generator syscall
```

Expected output:
```
jsa_infrasec_watchers_active{source="falco"} 1
jsa_infrasec_watchers_active{source="k8s_events"} 1
jsa_infrasec_findings_total{severity="critical"} 0
```

---

## Upgrade Path

### From v1.x to v2.x

```bash
# Backup existing config
helm get values jsa-infrasec -n gp-security > backup-values.yaml

# Upgrade
helm upgrade jsa-infrasec gp-copilot/jsa-infrasec \
  --namespace gp-security \
  -f my-values.yaml \
  --reuse-values

# Verify
kubectl rollout status -n gp-security deployment/jsa-infrasec
```

---

*Part of the Iron Legion - CKS | CKA | CCSP Certified Standards*

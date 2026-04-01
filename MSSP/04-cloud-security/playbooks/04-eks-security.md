# 04 — EKS Security

> Harden EKS: private endpoint, envelope encryption, logging, IRSA, PSS.

EKS gives you a managed control plane. That means you can't change API server flags — but there's plenty you CAN harden. This playbook covers the AWS-specific controls that sit underneath the Kubernetes hardening in 02-platform-hardening.

For AKS or GKE, the concepts are the same — the commands differ. AWS is the default; equivalents are noted.

---

## Step 1: Restrict API Endpoint Access

### AWS
```bash
# Make the endpoint private-only (recommended for production)
aws eks update-cluster-config --name $CLUSTER \
  --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true

# Or restrict to specific CIDRs (if you need public access from CI/CD)
aws eks update-cluster-config --name $CLUSTER \
  --resources-vpc-config endpointPublicAccess=true,publicAccessCidrs='["10.0.0.0/8","YOUR_CI_IP/32"]'
```

### AKS equivalent
```bash
az aks update --name $CLUSTER --resource-group $RG --enable-private-cluster
```

### GKE equivalent
```bash
gcloud container clusters update $CLUSTER --enable-private-endpoint --master-authorized-networks $CIDR
```

---

## Step 2: Enable All Control Plane Log Types

### AWS
```bash
aws eks update-cluster-config --name $CLUSTER \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

### AKS
```bash
az monitor diagnostic-settings create --name eks-logs --resource $CLUSTER_ID \
  --logs '[{"category":"kube-apiserver","enabled":true},{"category":"kube-audit","enabled":true}]'
```

---

## Step 3: Enable Envelope Encryption (Secrets at Rest)

### AWS
```bash
aws eks associate-encryption-config --cluster-name $CLUSTER \
  --encryption-config '[{"resources":["secrets"],"provider":{"keyArn":"arn:aws:kms:REGION:ACCOUNT:key/KEY_ID"}}]'
```

---

## Step 4: Set Up IRSA

See [02-iam-hardening.md](02-iam-hardening.md) Step 5 for the full IRSA setup. Every pod that talks to AWS should use IRSA — never static credentials.

---

## Step 5: Enforce IMDSv2 on Nodes

```bash
# For managed node groups — update the launch template
aws ec2 modify-instance-metadata-options --instance-id $NODE_ID \
  --http-tokens required --http-endpoint enabled --http-put-response-hop-limit 1
```

---

## Step 6: Enable ECR Scan-on-Push

```bash
aws ecr put-image-scanning-configuration --repository-name $REPO \
  --image-scanning-configuration scanOnPush=true
```

---

## Step 7: Apply Pod Security Standards

```bash
# Label all app namespaces
for ns in app-dev app-staging; do
  kubectl label namespace $ns \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite
done
```

---

## Step 8: Validate

```bash
bash tools/validate-aws-security.sh --check eks

# Or manually
aws eks describe-cluster --name $CLUSTER --query '{
  Endpoint: cluster.endpoint,
  PublicAccess: cluster.resourcesVpcConfig.endpointPublicAccess,
  Logging: cluster.logging.clusterLogging[0].enabled,
  Encryption: cluster.encryptionConfig[0].provider.keyArn
}'
```

---

## Next Step

Go to [05-monitoring-detection.md](05-monitoring-detection.md) to enable CloudTrail, GuardDuty, and Security Hub.

# 05 — Secrets Management

> Set up External Secrets Operator so secrets come from a vault, not from YAML files.

Kubernetes secrets are base64-encoded, not encrypted. Anyone with `kubectl get secret` can read them. External Secrets Operator syncs secrets from AWS Secrets Manager, HashiCorp Vault, or Azure Key Vault into Kubernetes — the actual secret value never lives in git.

In production, tools like CyberArk and Akeyless manage secrets at scale. ESO is the staging version — same pattern, open source.

---

## What You Need

- A secrets backend (AWS Secrets Manager, Vault, or Azure Key Vault)
- `kubectl` and `helm` access

---

## Step 1: Install External Secrets Operator

```bash
bash tools/setup-external-secrets.sh
```

Or manually:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true

kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=external-secrets \
  -n external-secrets --timeout=120s
```

---

## Step 2: Configure the Backend

### AWS Secrets Manager

```bash
# Create IAM role/policy for ESO (if not already done)
# Then create the SecretStore:
kubectl apply -f templates/external-secrets/clustersecretstore.yaml
```

Review the template first — it needs your AWS region and IAM role ARN:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

### HashiCorp Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault
  namespace: <your-namespace>
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
```

---

## Step 3: Create an ExternalSecret

```bash
kubectl apply -f templates/external-secrets/externalsecret.yaml
```

Example — sync a database password from AWS Secrets Manager:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials          # K8s Secret that gets created
    creationPolicy: Owner
  data:
  - secretKey: DB_PASSWORD        # key in the K8s Secret
    remoteRef:
      key: prod/app/database      # path in Secrets Manager
      property: password           # field in the JSON
```

---

## Step 4: Clean Up Orphaned Secrets

Find and remove secrets that aren't referenced by any pod:

```bash
bash tools/cleanup-orphaned-secrets.sh --dry-run
```

Review the list, then:
```bash
bash tools/cleanup-orphaned-secrets.sh
```

---

## Step 5: Enforce ESO-Only Secrets (Optional)

Deploy the Kyverno policy that bans creating native Opaque secrets:

```bash
kubectl apply -f policies/kyverno/custom/require-external-secrets.yaml
```

This forces all secrets to come through ESO. Native `kubectl create secret` gets blocked.

---

## Step 6: Verify

```bash
# Check ExternalSecret is synced
kubectl get externalsecret -A
# STATUS should be "SecretSynced"

# Check the K8s Secret was created
kubectl get secret db-credentials -n app -o jsonpath='{.data.DB_PASSWORD}' | base64 -d

# Check orphaned secrets are gone
kubectl get secrets --all-namespaces -o json | \
  jq -r '.items[] | select(.type=="Opaque") | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l
```

---

## Next Step

Go to [06-scan-and-verify.md](06-scan-and-verify.md) to scan the live cluster.

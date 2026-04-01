# 05 — Identity & Secrets (IA)

> NIST 800-53: IA-2, IA-5 — Multi-factor authentication, authenticator management.

---

## IA-2: Identification and Authentication

```bash
# AWS — all users have MFA?
aws iam generate-credential-report && sleep 5
aws iam get-credential-report --query Content --output text | base64 -d | \
  awk -F',' '$4=="true" && $8=="false" {print "NO MFA:", $1}'
# Expected: 0 output

# K8s — using OIDC for authentication (not static tokens)?
aws eks describe-cluster --name $CLUSTER --query 'cluster.identity.oidc'

# K8s — unique ServiceAccounts per workload (no sharing default SA)
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.serviceAccountName=="default") | "\(.metadata.namespace)/\(.metadata.name): using default SA"'
```

**Evidence:** All users have MFA, OIDC for kubectl, unique ServiceAccounts per workload.

---

## IA-5: Authenticator Management

### No Secrets in Code

```bash
# Verify Gitleaks is clean
gitleaks detect --source $TARGET_DIR --no-banner
# Expected: 0 findings

# Verify Gitleaks runs in CI
grep -l "gitleaks" $TARGET_DIR/.github/workflows/*.yml
```

### Secrets in Secrets Manager (Not YAML)

```bash
# Check for hardcoded secrets in K8s manifests
grep -rn "password\|secret\|api.key\|token" $TARGET_DIR/k8s/ --include="*.yaml" | grep -v "secretKeyRef\|ExternalSecret"

# Verify External Secrets are syncing
kubectl get externalsecret -A
# STATUS should all be "SecretSynced"
```

### Rotation

```bash
# AWS — secrets have rotation enabled?
aws secretsmanager list-secrets --query 'SecretList[*].[Name,RotationEnabled]' --output table

# K8s — no secrets older than 90 days
kubectl get secrets -A -o json | jq -r '.items[] | select(.type=="Opaque") | "\(.metadata.namespace)/\(.metadata.name) created:\(.metadata.creationTimestamp)"'
```

**Evidence:** 0 Gitleaks findings, secrets in Secrets Manager with rotation, no hardcoded credentials.

---

## Next Step

Go to [06-vulnerability-integrity.md](06-vulnerability-integrity.md).

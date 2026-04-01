# 01 — Access Control (AC)

> NIST 800-53: AC-2, AC-3, AC-6, AC-17 — Account management, access enforcement, least privilege, remote access.

---

## AC-2: Account Management

```bash
# K8s — audit ClusterRoleBindings
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name + " → " + (.subjects[]?.name // "unknown")'

# AWS — audit IAM users
aws iam generate-credential-report && sleep 5
aws iam get-credential-report --query Content --output text | base64 -d | \
  awk -F',' 'NR>1 {print $1, "MFA:"$8, "LastUsed:"$5}'
```

**Evidence:** Quarterly account review showing inactive accounts disabled, cluster-admin bindings documented.

---

## AC-3: Access Enforcement

```bash
# Verify RBAC is the only authorization mode
kubectl api-versions | grep rbac

# Verify no anonymous access
kubectl auth can-i list pods --as=system:anonymous
# Expected: no
```

**Evidence:** RBAC enabled, anonymous access denied, Kyverno enforcing.

---

## AC-6: Least Privilege

```bash
# Find pods running as root
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.containers[].securityContext.runAsNonRoot != true) | "\(.metadata.namespace)/\(.metadata.name)"'

# Apply Kyverno policies
kubectl apply -f policies/kyverno/
```

**Evidence:** 0 pods running as root (except documented exceptions), Kyverno policies in enforce mode.

---

## AC-17: Remote Access

```bash
# EKS — verify private endpoint
aws eks describe-cluster --name $CLUSTER --query 'cluster.resourcesVpcConfig.endpointPublicAccess'
# Expected: false (or restricted CIDRs)
```

**Evidence:** API endpoint private or CIDR-restricted, OIDC for kubectl auth.

---

## Next Step

Go to [02-audit-logging.md](02-audit-logging.md).

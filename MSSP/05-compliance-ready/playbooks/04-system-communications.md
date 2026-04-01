# 04 — System Communications (SC)

> NIST 800-53: SC-7, SC-8, SC-12, SC-28 — Boundary protection, TLS, crypto key management, encryption at rest.

---

## SC-7: Boundary Protection

```bash
# Verify every namespace has a default-deny NetworkPolicy
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v kube-); do
  count=$(kubectl get networkpolicy -n $ns --no-headers 2>/dev/null | wc -l)
  [ "$count" -eq 0 ] && echo "NO POLICY: $ns"
done
# Expected: 0 output (every namespace has policies)
```

**Evidence:** Default-deny NetworkPolicy in every namespace, per-service allow rules documented.

---

## SC-8: Transmission Confidentiality

```bash
# Verify external TLS (ingress/gateway)
kubectl get ingress -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) TLS:\(.spec.tls[0].secretName // "NONE")"'

# Verify internal mTLS (if Istio/Cilium)
istioctl authn tls-check $(kubectl get pods -n app -o jsonpath='{.items[0].metadata.name}') 2>/dev/null || echo "No service mesh"
```

**Evidence:** All external traffic over TLS, internal mTLS if service mesh is deployed.

---

## SC-12: Cryptographic Key Management

```bash
# Verify KMS keys exist and have rotation enabled
aws kms list-keys --query 'Keys[*].KeyId' --output text | while read key; do
  rotation=$(aws kms get-key-rotation-status --key-id $key --query 'KeyRotationEnabled' 2>/dev/null)
  alias=$(aws kms list-aliases --key-id $key --query 'Aliases[0].AliasName' --output text 2>/dev/null)
  echo "$alias: rotation=$rotation"
done
```

**Evidence:** KMS keys with annual rotation enabled for every service.

---

## SC-28: Protection of Information at Rest

```bash
# S3 — all buckets encrypted?
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  enc=$(aws s3api get-bucket-encryption --bucket $b 2>/dev/null | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' 2>/dev/null)
  echo "$b: ${enc:-NOT ENCRYPTED}"
done

# EBS — default encryption enabled?
aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault'

# RDS — encrypted?
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,StorageEncrypted]' --output table

# K8s Secrets — envelope encryption?
aws eks describe-cluster --name $CLUSTER --query 'cluster.encryptionConfig[0].provider.keyArn'
```

**Evidence:** All storage encrypted with KMS, default EBS encryption enabled, K8s secrets envelope-encrypted.

---

## Next Step

Go to [05-identity-secrets.md](05-identity-secrets.md).

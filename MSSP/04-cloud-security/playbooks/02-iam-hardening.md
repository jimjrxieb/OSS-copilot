# 02 — IAM Hardening

> Lock down root, enforce MFA, kill stale credentials, scope permissions.

IAM is where most cloud breaches start. Overly broad permissions, stale access keys, and missing MFA are the top three findings on every cloud security audit.

---

## Step 1: Lock Down Root

### AWS
```bash
# Verify: no root access keys
aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent'
# Expected: 0

# Verify: root has MFA
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled'
# Expected: 1
```

### Azure
```bash
# Check global admin accounts
az ad user list --query "[?contains(memberOf[].displayName, 'Global Administrator')]" --output table
```

### GCP
```bash
# List org-level IAM bindings (look for overly broad roles)
gcloud organizations get-iam-policy $ORG_ID --format json | jq '.bindings[] | select(.role=="roles/owner")'
```

---

## Step 2: Audit Users and MFA

### AWS
```bash
# Generate credential report
aws iam generate-credential-report
aws iam get-credential-report --query 'Content' --output text | base64 -d > $OUTPUT_DIR/iam-report.csv

# Find users without MFA
aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' '$4=="true" && $8=="false" {print "NO MFA:", $1}'

# Find stale access keys (>90 days)
aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' '$9=="true" {print $1, $10}' | while read user date; do
    age=$(( ($(date +%s) - $(date -d "$date" +%s)) / 86400 ))
    [ $age -gt 90 ] && echo "STALE ($age days): $user"
  done
```

### Azure
```bash
az ad user list --query "[].{Name:displayName, MFA:strongAuthenticationDetail}" --output table
```

### GCP
```bash
gcloud iam service-accounts keys list --iam-account $SA_EMAIL --format json | \
  jq '.[] | select(.validAfterTime < "2024-01-01")'
```

---

## Step 3: Kill Stale Credentials

### AWS
```bash
# Deactivate old access keys
aws iam update-access-key --user-name <user> --access-key-id <key-id> --status Inactive

# Delete after confirming nothing breaks
aws iam delete-access-key --user-name <user> --access-key-id <key-id>
```

---

## Step 4: Audit for Wildcard Permissions

### AWS
```bash
bash tools/iam-audit.sh --output $OUTPUT_DIR

# Or manually — find policies with Action: "*"
aws iam list-policies --scope Local --query 'Policies[*].Arn' --output text | while read arn; do
  aws iam get-policy-version --policy-arn $arn --version-id $(aws iam get-policy --policy-arn $arn --query 'Policy.DefaultVersionId' --output text) \
    --query 'PolicyVersion.Document' --output json | grep -l '"Action": "\*"' && echo "WILDCARD: $arn"
done
```

---

## Step 5: Set Up IRSA (AWS) / Workload Identity (GCP) / Pod Identity (Azure)

Service accounts should get cloud permissions through federation, not static keys.

### AWS (IRSA)
```bash
# Create OIDC provider for EKS
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

# Create IAM role with OIDC trust
aws iam create-role --role-name app-s3-reader \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {"StringEquals": {
        "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:app:app-sa"
      }}
    }]
  }'

# Annotate the K8s ServiceAccount
kubectl annotate serviceaccount app-sa -n app \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/app-s3-reader
```

### GCP (Workload Identity)
```bash
gcloud iam service-accounts add-iam-policy-binding $GSA_EMAIL \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:$PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]"
```

### Azure (Pod Identity)
```bash
az identity create --name app-identity --resource-group $RG
az aks pod-identity add --cluster-name $CLUSTER --resource-group $RG \
  --namespace app --name app-identity --identity-resource-id $IDENTITY_ID
```

---

## Step 6: Enable Access Analyzer

### AWS
```bash
aws accessanalyzer create-analyzer --analyzer-name account-analyzer --type ACCOUNT
# Review external access findings:
aws accessanalyzer list-findings --analyzer-arn $ANALYZER_ARN
```

---

## Step 7: Verify

```bash
bash tools/iam-audit.sh --output $OUTPUT_DIR
bash tools/validate-aws-security.sh --check iam
```

---

## Next Step

Go to [03-data-protection.md](03-data-protection.md) to encrypt everything.

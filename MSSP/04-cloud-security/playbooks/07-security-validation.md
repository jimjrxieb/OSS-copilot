# 07 — Security Validation

> Run the full audit. Prowler, Checkov, Kubescape — prove the cloud is hardened.

This is your before/after proof. Run the same scans the enterprise tools would run and produce a scorecard.

---

## Step 1: Run Prowler (AWS CIS + Best Practices)

### AWS
```bash
bash tools/prowler-scan.sh --output $OUTPUT_DIR

# Or manually
prowler aws --output-formats json-ocsf --output-directory $OUTPUT_DIR/prowler/
```

Prowler runs 300+ checks covering CIS AWS Foundations, NIST 800-53, PCI-DSS, and AWS best practices.

### Azure equivalent
```bash
prowler azure --output-formats json-ocsf --output-directory $OUTPUT_DIR/prowler/
```

### GCP equivalent
```bash
prowler gcp --output-formats json-ocsf --output-directory $OUTPUT_DIR/prowler/
```

---

## Step 2: Run Checkov on IaC

```bash
checkov -d $TARGET_DIR/terraform/ --output json > $OUTPUT_DIR/checkov-final.json
checkov -d $TARGET_DIR/terraform/ --compact
```

---

## Step 3: Run Kubescape on Live Cluster

```bash
kubescape scan --format pretty-printer --output $OUTPUT_DIR/kubescape-cloud.json
```

---

## Step 4: Run the Validation Script

```bash
bash tools/validate-aws-security.sh --output $OUTPUT_DIR/validation-report.md
```

This runs a 33-point checklist:

**Network:** SGs, Flow Logs, VPC endpoints, IMDSv2, NACLs
**IAM:** Root MFA, no wildcards, no stale creds, IRSA, Access Analyzer
**Encryption:** EBS, S3, RDS, KMS rotation, Secrets Manager
**EKS:** Private endpoint, 5 log types, envelope encryption, ECR scan
**Monitoring:** CloudTrail, GuardDuty, Security Hub, Config rules, alarms

---

## Step 5: Scorecard

```markdown
# Cloud Security Scorecard — <DATE>

| Category | Checks | Pass | Fail | Score |
|----------|--------|------|------|-------|
| Network | 7 | __ | __ | __% |
| IAM | 7 | __ | __ | __% |
| Encryption | 6 | __ | __ | __% |
| EKS | 6 | __ | __ | __% |
| Monitoring | 7 | __ | __ | __% |
| **Total** | **33** | __ | __ | __% |

Prowler findings: __ CRITICAL, __ HIGH, __ MEDIUM
Checkov findings: __ FAILED checks
```

---

## Next Step

Go to [08-incident-response.md](08-incident-response.md) for cloud incident runbooks.

# Playbook 03: Harden IAM

> IAM is the #1 attack vector in AWS. Overprivileged roles, stale keys,
> and missing MFA are how breaches start.
>
> **Time:** ~15 minutes
> **Prerequisites:** AWS CLI with IAM read access

---

## Why IAM First

Every AWS breach postmortem has the same root cause: someone had more
access than they needed. A leaked access key with `AdministratorAccess`
is game over. A leaked key scoped to `s3:GetObject` on one bucket is
contained.

IAM is the one thing you can harden for free, today, with no tools to install.

---

## Step 1: Root Account Lockdown

```bash
# Check if root has MFA
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled'
# 1 = MFA enabled (good)
# 0 = MFA NOT enabled (fix immediately)

# Check if root has access keys (should be 0)
aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent'
# 0 = no access keys (good)
# 1 = root has access keys (delete them)
```

**If root has no MFA:** Log into the root account, go to IAM → Security
credentials → Assign MFA device. Use a hardware key or authenticator app.

**If root has access keys:** Delete them. Root should never use access keys.

---

## Step 2: Find Users Without MFA

```bash
# List all users and their MFA status
aws iam generate-credential-report 2>/dev/null
sleep 5
aws iam get-credential-report --query 'Content' --output text | \
    base64 -d | \
    awk -F',' 'NR>1 {if ($4=="true" && $8=="false") print "  NO MFA: "$1}'
```

Every human user with console access must have MFA. No exceptions.

---

## Step 3: Find Stale Access Keys

```bash
# Keys older than 90 days
aws iam get-credential-report --query 'Content' --output text | \
    base64 -d | \
    python3 -c "
import csv, sys, datetime
reader = csv.DictReader(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
for row in reader:
    for key_field in ['access_key_1_last_rotated', 'access_key_2_last_rotated']:
        date_str = row.get(key_field, 'N/A')
        if date_str not in ('N/A', 'not_supported', ''):
            key_date = datetime.datetime.fromisoformat(date_str.replace('+00:00', '+00:00'))
            age = (now - key_date).days
            if age > 90:
                key_num = '1' if '1' in key_field else '2'
                print(f'  STALE ({age}d): {row[\"user\"]} — access_key_{key_num}')
"
```

**Keys older than 90 days:** Rotate or deactivate. If nobody remembers
what the key is for, deactivate it and wait 2 weeks. If nothing breaks,
delete it.

---

## Step 4: Find Overprivileged Policies

```bash
# IAM policies with wildcard actions or resources
aws iam list-policies --scope Local --query 'Policies[*].[PolicyName,Arn]' --output text | \
while read name arn; do
    VERSION=$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text)
    WILDCARDS=$(aws iam get-policy-version --policy-arn "$arn" --version-id "$VERSION" --query 'PolicyVersion.Document' --output json | \
        python3 -c "
import json, sys
doc = json.load(sys.stdin)
for stmt in doc.get('Statement', []):
    actions = stmt.get('Action', [])
    resources = stmt.get('Resource', [])
    if isinstance(actions, str): actions = [actions]
    if isinstance(resources, str): resources = [resources]
    if '*' in actions or '*' in resources:
        print(f'    Action={actions} Resource={resources}')
" 2>/dev/null)
    [ -n "$WILDCARDS" ] && echo "  WILDCARD: $name" && echo "$WILDCARDS"
done
```

### What to fix:

```json
// BAD: can do anything to any resource
{
    "Effect": "Allow",
    "Action": "*",
    "Resource": "*"
}

// GOOD: scoped to what the service actually needs
{
    "Effect": "Allow",
    "Action": [
        "s3:GetObject",
        "s3:PutObject"
    ],
    "Resource": "arn:aws:s3:::my-app-bucket/*"
}
```

---

## Step 5: Lint IAM Policies with Parliament

```bash
pip install parliament

# Scan a policy file
parliament --file my-policy.json

# Scan inline — paste your policy
echo '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": "s3:*",
        "Resource": "*"
    }]
}' | parliament --string
```

Parliament catches:
- Wildcard actions and resources
- Missing version statements
- Invalid action names
- Overly broad conditions

---

## Step 6: Enable IAM Access Analyzer

```bash
# Create an analyzer (one-time, per region)
aws accessanalyzer create-analyzer \
    --analyzer-name account-analyzer \
    --type ACCOUNT \
    --region us-east-1

# Check for findings (resources shared with external accounts)
aws accessanalyzer list-findings \
    --analyzer-arn "arn:aws:access-analyzer:us-east-1:$(aws sts get-caller-identity --query Account --output text):analyzer/account-analyzer" \
    --query 'findings[*].[resourceType,resource,status]' \
    --output table
```

Access Analyzer tells you if any resource (S3 bucket, IAM role, KMS key,
Lambda, SQS queue) is accessible from outside your account. This is free
and built into AWS.

---

## IAM Scorecard

```
IAM Security Scorecard
──────────────────────
Root MFA:                   Yes / No  (target: Yes)
Root access keys:           ___ (target: 0)
Users without MFA:          ___ (target: 0)
Stale keys (>90 days):      ___ (target: 0)
Policies with wildcards:    ___ (target: 0 custom policies)
Access Analyzer:            Enabled / Not enabled
```

---

## Next Steps

- Enable threat detection → [04-enable-detection.md](04-enable-detection.md)
- Track your posture → [05-track-your-posture.md](05-track-your-posture.md)

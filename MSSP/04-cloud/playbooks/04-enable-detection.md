# Playbook 04: Enable Detection

> Turn on CloudTrail, GuardDuty, and Security Hub. These are AWS-native
> services that replace $100-500K/yr in enterprise tooling. Most of them
> have a free tier.
>
> **Time:** ~15 minutes
> **Prerequisites:** AWS admin access

---

## Why This Matters

Three of the most powerful security tools are already in your AWS account.
They just need to be turned on. Most AWS accounts have none of them enabled.

| Service | What It Does | Enterprise Equivalent | Cost |
|---------|-------------|----------------------|------|
| **CloudTrail** | Logs every API call | Built into Wiz/Prisma | Free (90-day lookup), ~$2/100K events to S3 |
| **GuardDuty** | Threat detection (ML-based) | CrowdStrike ($50-200K) | ~$4/million events (30-day free trial) |
| **Security Hub** | Aggregates findings, CIS scoring | Splunk dashboards ($50-500K) | ~$0.0010/check (30-day free trial) |

---

## Step 1: Enable CloudTrail

CloudTrail logs every API call in your account. Without it, you have
no forensics trail if something goes wrong.

```bash
# Create an S3 bucket for CloudTrail logs
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="cloudtrail-logs-${ACCOUNT_ID}"

aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region us-east-1

# Block public access
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create the trail (multi-region — covers ALL regions)
aws cloudtrail create-trail \
    --name organization-trail \
    --s3-bucket-name "$BUCKET" \
    --is-multi-region-trail \
    --enable-log-file-validation

# Start logging
aws cloudtrail start-logging --name organization-trail

# Verify
aws cloudtrail get-trail-status --name organization-trail \
    --query '[IsLogging, LatestDeliveryTime]'
```

**Multi-region is critical.** An attacker who compromises your account will
operate in regions you don't monitor. Multi-region CloudTrail catches this.

---

## Step 2: Enable GuardDuty

GuardDuty uses machine learning to detect threats: compromised credentials,
cryptocurrency mining, data exfiltration, reconnaissance.

```bash
# Enable GuardDuty (one command)
aws guardduty create-detector --enable --finding-publishing-frequency FIFTEEN_MINUTES

# Verify it's running
aws guardduty list-detectors

# Check for findings (hopefully empty)
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty list-findings --detector-id "$DETECTOR_ID" \
    --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}' \
    --query 'FindingIds'
```

### What GuardDuty detects:

| Finding Type | What It Means | Severity |
|-------------|--------------|----------|
| `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` | Someone using EC2 instance creds outside AWS | Critical |
| `CryptoCurrency:EC2/BitcoinTool.B` | EC2 instance mining crypto | High |
| `Recon:EC2/PortProbeUnprotectedPort` | Someone probing open ports | Medium |
| `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B` | Successful login from unusual location | Medium |
| `Trojan:EC2/DNSDataExfiltration` | Data being exfiltrated via DNS | High |

**GuardDuty has a 30-day free trial.** After that, it costs ~$4 per million
CloudTrail events analyzed. For most accounts, this is $10-50/month — far
cheaper than CrowdStrike's $50-200K/yr.

---

## Step 3: Enable Security Hub

Security Hub aggregates findings from GuardDuty, Prowler, Inspector, and
Config Rules into one dashboard with CIS benchmark scoring.

```bash
# Enable Security Hub with CIS and AWS Foundational standards
aws securityhub enable-security-hub \
    --enable-default-standards

# Verify
aws securityhub describe-hub

# Check your compliance score
aws securityhub get-findings \
    --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}' \
    --query 'Findings | length(@)'
```

**After enabling Security Hub:**
- CIS AWS Foundations Benchmark runs automatically
- AWS Foundational Security Best Practices runs automatically
- GuardDuty findings appear in Security Hub
- Prowler can push findings here too (see Playbook 01)

---

## Step 4: Enable VPC Flow Logs

```bash
# Get your VPC ID
VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)

# Create CloudWatch log group
aws logs create-log-group --log-group-name "vpc-flow-logs"

# Enable flow logs on the VPC
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids "$VPC_ID" \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name "vpc-flow-logs" \
    --deliver-logs-permission-arn "arn:aws:iam::${ACCOUNT_ID}:role/VPCFlowLogsRole"
```

Flow logs record every network connection in your VPC — source, destination,
port, accept/reject. Essential for forensics and threat hunting.

---

## Step 5: Set Up Critical Alerts

Five CloudWatch metric filters that catch the most important events:

```bash
LOG_GROUP="CloudTrail/DefaultLogGroup"  # Adjust to your CloudTrail log group
SNS_TOPIC="arn:aws:sns:us-east-1:${ACCOUNT_ID}:security-alerts"

# 1. Root account usage
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "RootAccountUsage" \
    --filter-pattern '{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }' \
    --metric-transformations metricName=RootAccountUsage,metricNamespace=SecurityAlerts,metricValue=1

# 2. Console login without MFA
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "ConsoleLoginWithoutMFA" \
    --filter-pattern '{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") }' \
    --metric-transformations metricName=ConsoleLoginWithoutMFA,metricNamespace=SecurityAlerts,metricValue=1

# 3. IAM policy changes
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "IAMPolicyChanges" \
    --filter-pattern '{ ($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy) }' \
    --metric-transformations metricName=IAMPolicyChanges,metricNamespace=SecurityAlerts,metricValue=1
```

These three filters catch: root account being used (should never happen),
logins without MFA (policy violation), and IAM changes (privilege escalation
attempt or misconfiguration).

---

## Step 6: Verify Everything

```bash
echo "=== Detection Stack Status ==="

# CloudTrail
echo -n "CloudTrail: "
aws cloudtrail get-trail-status --name organization-trail --query 'IsLogging' --output text 2>/dev/null || echo "NOT CONFIGURED"

# GuardDuty
echo -n "GuardDuty: "
aws guardduty list-detectors --query 'DetectorIds | length(@)' --output text 2>/dev/null
echo " detector(s)"

# Security Hub
echo -n "Security Hub: "
aws securityhub describe-hub --query 'HubArn' --output text 2>/dev/null || echo "NOT ENABLED"

# VPC Flow Logs
echo -n "VPC Flow Logs: "
aws ec2 describe-flow-logs --query 'FlowLogs | length(@)' --output text 2>/dev/null
echo " flow log(s)"
```

---

## What You Just Built (For Free)

```
CloudTrail    → Every API call logged (forensics)
GuardDuty     → ML-based threat detection (alerts)
Security Hub  → CIS benchmark scoring (compliance)
Flow Logs     → Network traffic records (visibility)
Metric Filters → Critical event alerts (response)
```

This is the detection stack that enterprise tools like CrowdStrike ($50-200K/yr)
and Splunk ($50-500K/yr) provide. The AWS-native version costs $50-200/month
for a typical account and catches the same classes of threats.

---

## Next Steps

- Track your posture over time → [05-track-your-posture.md](05-track-your-posture.md)
- Back to overview → [../README.md](../README.md)

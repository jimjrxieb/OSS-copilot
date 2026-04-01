# 05 — Monitoring & Detection

> Enable CloudTrail, GuardDuty, Security Hub, and Config. The four pillars of AWS detection.

These are the cloud-native detection services. They're cheap, easy to enable, and most organizations have at least two of them turned off. Fix that here.

---

## Step 1: CloudTrail

### AWS
```bash
# Create trail bucket
aws s3api create-bucket --bucket ${ACCOUNT_ID}-cloudtrail --region us-east-1

# Create multi-region trail
aws cloudtrail create-trail --name org-trail \
  --s3-bucket-name ${ACCOUNT_ID}-cloudtrail \
  --is-multi-region-trail --enable-log-file-validation

aws cloudtrail start-logging --name org-trail

# Enable data events (S3 + Lambda)
aws cloudtrail put-event-selectors --trail-name org-trail \
  --event-selectors '[{"ReadWriteType":"All","IncludeManagementEvents":true,"DataResources":[{"Type":"AWS::S3::Object","Values":["arn:aws:s3"]}]}]'
```

### Azure equivalent
```bash
az monitor activity-log list --resource-group $RG --start-time $(date -d '-30 days' +%Y-%m-%d)
az monitor diagnostic-settings create --name audit --resource $RESOURCE_ID \
  --storage-account $STORAGE --logs '[{"category":"AuditEvent","enabled":true}]'
```

### GCP equivalent
```bash
# Audit logs are on by default in GCP. Verify:
gcloud logging read "logName:activity" --project=$PROJECT --limit=5
```

---

## Step 2: GuardDuty

### AWS
```bash
aws guardduty create-detector --enable --finding-publishing-frequency FIFTEEN_MINUTES

# Enable optional features
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty update-detector --detector-id $DETECTOR_ID \
  --features '[
    {"Name":"EKS_AUDIT_LOGS","Status":"ENABLED"},
    {"Name":"EKS_RUNTIME_MONITORING","Status":"ENABLED"},
    {"Name":"LAMBDA_NETWORK_LOGS","Status":"ENABLED"},
    {"Name":"S3_DATA_EVENTS","Status":"ENABLED"}
  ]'
```

### Azure equivalent
```bash
az security pricing create --name VirtualMachines --tier standard
az security auto-provisioning-setting update --name default --auto-provision on
```

### GCP equivalent
```bash
gcloud scc notifications create threat-alerts --organization=$ORG_ID \
  --pubsub-topic=projects/$PROJECT/topics/security-alerts \
  --filter='category="THREAT"'
```

---

## Step 3: Security Hub

### AWS
```bash
aws securityhub enable-security-hub --enable-default-standards

# Enable CIS AWS Foundations
aws securityhub batch-enable-standards --standards-subscription-requests \
  '[{"StandardsArn":"arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"}]'

# Enable AWS Foundational Best Practices
aws securityhub batch-enable-standards --standards-subscription-requests \
  '[{"StandardsArn":"arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"}]'
```

---

## Step 4: AWS Config

### AWS
```bash
# Enable Config recorder
aws configservice put-configuration-recorder --configuration-recorder \
  name=default,roleARN=$CONFIG_ROLE_ARN,recordingGroup={allSupported=true}

aws configservice start-configuration-recorder --configuration-recorder-name default

# Deploy managed rules
for rule in s3-bucket-server-side-encryption-enabled encrypted-volumes \
  rds-storage-encrypted iam-user-mfa-enabled root-account-mfa-enabled \
  vpc-flow-logs-enabled guardduty-enabled-centralized cloudtrail-enabled; do
  aws configservice put-config-rule --config-rule \
    "{\"ConfigRuleName\":\"$rule\",\"Source\":{\"Owner\":\"AWS\",\"SourceIdentifier\":\"$(echo $rule | tr '-' '_' | tr '[:lower:]' '[:upper:]')\"}}"
done
```

---

## Step 5: CloudWatch Alarms

### AWS
```bash
# Create SNS topic for security alerts
aws sns create-topic --name security-alerts
aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint security@example.com

# Root login alarm
aws logs put-metric-filter --log-group-name CloudTrail/logs --filter-name RootLogin \
  --filter-pattern '{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }' \
  --metric-transformations metricName=RootLoginCount,metricNamespace=Security,metricValue=1

aws cloudwatch put-metric-alarm --alarm-name RootLogin \
  --metric-name RootLoginCount --namespace Security \
  --statistic Sum --period 300 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions $TOPIC_ARN
```

---

## Step 6: Validate

```bash
bash tools/validate-aws-security.sh --check monitoring

# Quick manual checks
aws cloudtrail get-trail-status --name org-trail --query 'IsLogging'
aws guardduty list-detectors --query 'DetectorIds'
aws securityhub describe-hub --query 'HubArn'
aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].recording'
```

---

## Next Step

Go to [06-ecr-cicd-pipeline.md](06-ecr-cicd-pipeline.md) to set up secure container image delivery.

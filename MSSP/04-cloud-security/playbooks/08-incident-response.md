# 08 — Incident Response (Cloud)

> Runbooks for the four most common cloud incidents: compromised credentials, public S3, rogue EC2, unauthorized IAM role.

When GuardDuty fires or Security Hub flags something, follow these steps. Each incident type has: detect, contain, investigate, eradicate, recover.

---

## Incident 1: Compromised Access Key

**Detect:** GuardDuty `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` or unusual API calls from unexpected IP.

### AWS
```bash
# 1. CONTAIN — disable the key immediately
aws iam update-access-key --user-name $USER --access-key-id $KEY_ID --status Inactive

# 2. INVESTIGATE — what did they do?
aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=$KEY_ID \
  --max-results 50 --query 'Events[*].[EventTime,EventName,Resources[0].ResourceName]' --output table

# 3. ERADICATE — delete the key, rotate all secrets it could access
aws iam delete-access-key --user-name $USER --access-key-id $KEY_ID

# 4. RECOVER — issue new credentials with tighter scope
aws iam create-access-key --user-name $USER
```

### Azure equivalent
```bash
az ad user update --id $USER_ID --account-enabled false
az monitor activity-log list --caller $USER_ID --start-time $(date -d '-7 days' +%Y-%m-%d)
```

### GCP equivalent
```bash
gcloud iam service-accounts keys disable $KEY_ID --iam-account=$SA_EMAIL
gcloud logging read "protoPayload.authenticationInfo.principalEmail=$SA_EMAIL" --limit=50
```

---

## Incident 2: Public S3 Bucket

**Detect:** Security Hub `S3.2` or AWS Config `s3-bucket-public-read-prohibited`.

### AWS
```bash
# 1. CONTAIN — block public access immediately
aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 2. INVESTIGATE — was anything accessed?
aws s3api get-bucket-acl --bucket $BUCKET
aws s3api get-bucket-policy --bucket $BUCKET
# Check access logs if enabled

# 3. ERADICATE — fix the policy/ACL
aws s3api delete-bucket-policy --bucket $BUCKET

# 4. VERIFY
aws s3api get-public-access-block --bucket $BUCKET
```

---

## Incident 3: Rogue EC2 Instance

**Detect:** GuardDuty `Recon:EC2/PortProbeUnprotectedPort` or unexpected instance in billing.

### AWS
```bash
# 1. CONTAIN — quarantine with empty security group
aws ec2 create-security-group --group-name quarantine --description "No rules" --vpc-id $VPC_ID
aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --groups $QUARANTINE_SG

# 2. PRESERVE — snapshot before touching
aws ec2 create-snapshot --volume-id $VOLUME_ID --description "Forensics: $INSTANCE_ID"

# 3. INVESTIGATE
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=$INSTANCE_ID \
  --query 'Events[*].[EventTime,EventName,Username]' --output table

aws ec2 describe-vpc-flow-logs --filter "Name=resource-id,Values=$INSTANCE_ID"

# 4. ERADICATE
aws ec2 stop-instances --instance-ids $INSTANCE_ID
aws ec2 terminate-instances --instance-ids $INSTANCE_ID  # after investigation complete
```

---

## Incident 4: Unauthorized IAM Role

**Detect:** Access Analyzer finding or unexpected `sts:AssumeRole` in CloudTrail.

### AWS
```bash
# 1. CONTAIN — deny all actions
aws iam put-role-policy --role-name $ROLE --policy-name emergency-deny \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'

# 2. INVESTIGATE — who created it? who assumed it?
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateRole \
  --query 'Events[?contains(Resources[].ResourceName, `'$ROLE'`)].[EventTime,Username]' --output table

aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --query 'Events[?contains(requestParameters, `'$ROLE'`)].[EventTime,sourceIPAddress]' --output table

# 3. ERADICATE
aws iam delete-role-policy --role-name $ROLE --policy-name emergency-deny
aws iam delete-role --role-name $ROLE
```

---

## Evidence Preservation

Always preserve evidence before eradicating:

```bash
# Snapshot EBS volumes
aws ec2 create-snapshot --volume-id $VOL --description "Incident evidence $(date +%Y%m%d)"

# Export CloudTrail to dedicated bucket with object lock
aws s3api put-object-lock-configuration --bucket evidence-bucket \
  --object-lock-configuration '{
    "ObjectLockEnabled": "Enabled",
    "Rule": {"DefaultRetention": {"Mode": "COMPLIANCE", "Days": 365}}
  }'
```

---

## What's Next

Cloud security is done. Your IaC is scanned, VPC is hardened, IAM is locked down, detection is enabled, and you have incident runbooks.

Next package:
- **05-compliance-ready** — NIST mapping, FedRAMP evidence, documentation

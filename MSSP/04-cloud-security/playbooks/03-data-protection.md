# 03 — Data Protection

> Encrypt everything at rest and in transit. KMS keys, S3, RDS, EBS, Secrets Manager.

If it stores data, it gets encrypted. If it transmits data, it uses TLS. No exceptions.

---

## Step 1: Create KMS Keys

### AWS
```bash
# One key per service (audit trail clarity)
for purpose in eks s3 rds secrets ebs; do
  aws kms create-key --description "$purpose encryption key" \
    --tags TagKey=Purpose,TagValue=$purpose
  aws kms create-alias --alias-name alias/$purpose-key --target-key-id $KEY_ID
  aws kms enable-key-rotation --key-id $KEY_ID
done
```

### Azure
```bash
az keyvault create --name app-kv --resource-group $RG --enable-purge-protection true
az keyvault key create --vault-name app-kv --name app-key --kty RSA --size 2048
```

### GCP
```bash
gcloud kms keyrings create app-keyring --location=us-central1
gcloud kms keys create app-key --keyring=app-keyring --location=us-central1 --purpose=encryption
```

---

## Step 2: Block Public S3 Access

### AWS (account-wide)
```bash
aws s3control put-public-access-block --account-id $ACCOUNT_ID \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### Create a hardened bucket
```bash
aws s3api create-bucket --bucket $BUCKET --region us-east-1

# Encryption
aws s3api put-bucket-encryption --bucket $BUCKET \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms", "KMSMasterKeyID": "alias/s3-key"}}]
  }'

# Versioning
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled

# HTTPS only
aws s3api put-bucket-policy --bucket $BUCKET --policy '{
  "Statement": [{"Sid": "DenyHTTP", "Effect": "Deny", "Principal": "*",
    "Action": "s3:*", "Resource": ["arn:aws:s3:::'$BUCKET'/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}}]
}'
```

---

## Step 3: Enable Default EBS Encryption

### AWS
```bash
aws ec2 enable-ebs-encryption-by-default
aws ec2 modify-ebs-default-kms-key-id --kms-key-id alias/ebs-key
```

---

## Step 4: Configure Secrets Manager

### AWS
```bash
aws secretsmanager create-secret --name app/database \
  --secret-string '{"username":"app","password":"CHANGE_ME"}' \
  --kms-key-id alias/secrets-key

# Enable rotation (Lambda-based)
aws secretsmanager rotate-secret --secret-id app/database \
  --rotation-lambda-arn $ROTATION_LAMBDA_ARN \
  --rotation-rules AutomaticallyAfterDays=90
```

### Azure
```bash
az keyvault secret set --vault-name app-kv --name db-password --value "CHANGE_ME"
```

### GCP
```bash
echo -n "CHANGE_ME" | gcloud secrets create db-password --data-file=-
```

---

## Step 5: Validate Encryption

### AWS
```bash
# S3 — all buckets encrypted?
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  enc=$(aws s3api get-bucket-encryption --bucket $b 2>/dev/null | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' 2>/dev/null)
  echo "$b: ${enc:-NOT ENCRYPTED}"
done

# EBS — any unencrypted volumes?
aws ec2 describe-volumes --query 'Volumes[?Encrypted==`false`].[VolumeId,State]' --output table

# RDS — encrypted?
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,StorageEncrypted]' --output table
```

---

## Next Step

Go to [04-eks-security.md](04-eks-security.md) to harden EKS.

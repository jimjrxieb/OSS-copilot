# 01 — VPC & Network Security

> Build a hardened VPC with private subnets, security groups, flow logs, and VPC endpoints.

Every cloud deployment starts with networking. Get this wrong and everything built on top is exposed.

---

## Step 1: Create the VPC

### AWS (default)
```bash
# VPC + subnets
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=app-vpc}]'

# Private subnets (app workloads go here)
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1a}]'
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1b}]'

# Public subnets (ALB only)
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.101.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1a}]'
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.102.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1b}]'
```

Or use the Terraform template: `iac-templates/vpc-simple.tf`

### Azure equivalent
```bash
az network vnet create --name app-vnet --resource-group $RG --address-prefix 10.0.0.0/16
az network vnet subnet create --vnet-name app-vnet --name private --address-prefix 10.0.1.0/24
```

### GCP equivalent
```bash
gcloud compute networks create app-vpc --subnet-mode=custom
gcloud compute networks subnets create private --network=app-vpc --range=10.0.1.0/24 --region=us-central1
```

---

## Step 2: Security Groups (SG-to-SG References)

**Never use CIDR-based rules between your own services.** Reference security groups directly — if a service moves IPs, the rule still works.

### AWS
```bash
# ALB security group — public internet to ALB only
aws ec2 create-security-group --group-name alb-sg --description "ALB" --vpc-id $VPC_ID
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0

# App security group — ALB to app only
aws ec2 create-security-group --group-name app-sg --description "App" --vpc-id $VPC_ID
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 8080 --source-group $ALB_SG

# Database security group — app to DB only
aws ec2 create-security-group --group-name db-sg --description "DB" --vpc-id $VPC_ID
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 5432 --source-group $APP_SG
```

### Azure equivalent
```bash
az network nsg create --name app-nsg --resource-group $RG
az network nsg rule create --nsg-name app-nsg --name allow-alb --priority 100 \
  --source-address-prefixes 10.0.101.0/24 --destination-port-ranges 8080 --access Allow
```

### GCP equivalent
```bash
gcloud compute firewall-rules create allow-alb-to-app --network=app-vpc \
  --source-tags=alb --target-tags=app --allow=tcp:8080
```

---

## Step 3: Enable VPC Flow Logs

### AWS
```bash
aws ec2 create-flow-logs --resource-type VPC --resource-ids $VPC_ID \
  --traffic-type ALL --log-destination-type cloud-watch-logs \
  --log-group-name /vpc/flow-logs --deliver-logs-permission-arn $FLOW_LOG_ROLE_ARN
```

### Azure
```bash
az network watcher flow-log create --resource-group $RG --name flowlog \
  --nsg app-nsg --storage-account $STORAGE --enabled true
```

### GCP
```bash
gcloud compute networks subnets update private --region=us-central1 --enable-flow-logs
```

---

## Step 4: VPC Endpoints (Avoid NAT Gateway Costs)

### AWS
```bash
# Gateway endpoints (free)
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID --service-name com.amazonaws.us-east-1.s3 --route-table-ids $RT_ID
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID --service-name com.amazonaws.us-east-1.dynamodb --route-table-ids $RT_ID

# Interface endpoints (pennies, but saves NAT costs)
for svc in ecr.api ecr.dkr sts logs kms secretsmanager; do
  aws ec2 create-vpc-endpoint --vpc-id $VPC_ID --vpc-endpoint-type Interface \
    --service-name com.amazonaws.us-east-1.$svc --subnet-ids $PRIVATE_SUBNET_IDS --security-group-ids $ENDPOINT_SG
done
```

---

## Step 5: Enforce IMDSv2

Block the old metadata endpoint (credential theft vector):

### AWS
```bash
aws ec2 modify-instance-metadata-options --instance-id $INSTANCE_ID \
  --http-tokens required --http-endpoint enabled
```

---

## Step 6: Validate

```bash
bash tools/validate-aws-security.sh --check network
```

---

## Next Step

Go to [02-iam-hardening.md](02-iam-hardening.md) to lock down identity and access.

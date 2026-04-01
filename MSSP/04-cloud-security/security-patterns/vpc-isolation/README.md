# VPC Isolation Pattern

## Overview
Production-ready Multi-AZ VPC with public/private subnet isolation, NAT Gateways for egress control, and VPC Flow Logs for visibility.

## Flashcard Mapping
**Goal:** Isolate workloads
**Practice:** Multi-AZ VPC with public/private subnets
**Tool:** VPC/Subnets

## Quick Start

```bash
# Deploy VPC
cd terraform-template/
terraform init
terraform plan -var="project_name=myproject"
terraform apply

# Validate with OPA
conftest test . -p ../opa-policy.rego
```

## Architecture
- **Public Subnets:** ALB/NLB only (no workloads)
- **Private Subnets:** All application workloads
- **NAT Gateway:** One per AZ for fault isolation
- **Flow Logs:** All network traffic logged to CloudWatch

## Compliance
- CIS AWS Foundations: 5.1, 5.2, 5.3, 5.4, 3.7, 3.9
- PCI-DSS: 1.2.1, 1.3.1, 1.3.4, 10.1
- HIPAA: 164.308(a)(1)(ii)(D), 164.312(e)(1)
- FedRAMP: AC-4, AU-2, AU-6, SC-7

## Cost
~$160/month (with S3 log archival)
~$393/month (real-time CloudWatch logging)

See [compliance-mapping.md](compliance-mapping.md) for details.

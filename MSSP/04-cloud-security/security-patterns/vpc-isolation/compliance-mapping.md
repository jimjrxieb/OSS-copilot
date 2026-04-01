# VPC Isolation Pattern - Compliance Mapping

## Pattern Overview
**Pattern ID:** `vpc-isolation-001`
**Pattern Name:** Multi-AZ VPC with Public/Private Subnet Isolation
**Version:** 1.0.0
**Last Updated:** 2025-10-08

## CIS AWS Foundations Benchmark Mappings

| CIS Control | Description | Implementation | Validation |
|-------------|-------------|----------------|------------|
| **5.1** | Ensure no Network ACLs allow ingress from 0.0.0.0/0 to remote server administration ports | Default NACL denies all traffic. Custom NACLs required per subnet tier. | OPA policy + tfsec |
| **5.2** | Ensure no security groups allow ingress from 0.0.0.0/0 to port 3389 (RDP) | Default SG has no rules. Workloads in private subnets with SG chaining. | OPA policy |
| **5.3** | Ensure no security groups allow ingress from 0.0.0.0/0 to port 22 (SSH) | `map_public_ip_on_launch=false` on all subnets. Explicit EIP assignment only. | OPA policy |
| **5.4** | Ensure the default security group of every VPC restricts all traffic | Default SG explicitly configured with zero ingress/egress rules. | OPA policy |
| **3.7** | Ensure CloudWatch log groups are encrypted at rest | KMS encryption on VPC Flow Logs CloudWatch Log Group. | OPA policy |
| **3.9** | Ensure VPC flow logging is enabled in all VPCs | Flow Logs enabled with `traffic_type=ALL`, 90-day retention. | OPA policy |

## PCI-DSS 3.2.1 Mappings

| Requirement | Description | Implementation | Notes |
|-------------|-------------|----------------|-------|
| **1.2.1** | Restrict inbound and outbound traffic to that which is necessary for the cardholder data environment (CDE) | Private subnets with NAT Gateway for controlled egress. | Workloads in private subnets cannot accept inbound from internet |
| **1.3.1** | Implement a DMZ to limit inbound traffic to only system components that provide authorized publicly accessible services | Public subnets act as DMZ. Only ALB/NLB allowed. No workloads. | Public subnet = ALB only |
| **1.3.4** | Do not allow unauthorized outbound traffic from the cardholder data environment to the internet | NAT Gateway provides single egress point. Add Network Firewall for URL filtering. | Optional: Network Firewall |
| **10.1** | Implement audit trails to link all access to system components to each individual user | VPC Flow Logs capture source IP, destination, protocol, action (ACCEPT/REJECT). | Logs retained 90 days |

## HIPAA Security Rule Mappings

| Standard | Implementation Specification | Implementation | Compliance Status |
|----------|------------------------------|----------------|-------------------|
| **164.308(a)(1)(ii)(D)** | Information System Activity Review | VPC Flow Logs provide audit trail of all network activity | Required |
| **164.312(a)(1)** | Access Control - Unique User Identification | Network segmentation (public/private subnets) isolates PHI workloads | Required |
| **164.312(e)(1)** | Transmission Security | Private subnets prevent direct internet exposure of PHI. TLS required at application layer. | Required |
| **164.312(e)(2)(i)** | Integrity Controls | VPC Flow Logs immutable (KMS encrypted, 90-day retention) | Addressable |

## FedRAMP Moderate Mappings

| Control | Control Name | Implementation | Notes |
|---------|--------------|----------------|-------|
| **AC-4** | Information Flow Enforcement | Private subnets + NAT Gateway enforce egress control | Ingress denied by default |
| **AU-2** | Audit Events | VPC Flow Logs capture network events (source, dest, protocol, action) | 90-day retention |
| **AU-6** | Audit Review, Analysis, and Reporting | Flow Logs sent to CloudWatch for analysis via GuardDuty | Real-time threat detection |
| **SC-7** | Boundary Protection | Public/private subnet segmentation. Default SG denies all. | Defense in depth |

## Testing Checklist

- [ ] **Multi-AZ Deployment**
  - [ ] Minimum 2 availability zones deployed
  - [ ] Each AZ has public and private subnet
  - [ ] Route tables correctly associated

- [ ] **NAT Gateway High Availability**
  - [ ] One NAT Gateway per AZ (not shared)
  - [ ] Each private subnet routes to NAT in same AZ

- [ ] **VPC Flow Logs**
  - [ ] Flow Logs enabled on VPC
  - [ ] `traffic_type=ALL` (not just ACCEPT or REJECT)
  - [ ] CloudWatch Log Group exists with 90-day retention
  - [ ] KMS encryption enabled on log group

- [ ] **Network Isolation**
  - [ ] No auto-assign public IPs on any subnet
  - [ ] Default SG has zero ingress/egress rules
  - [ ] Default NACL denies all
  - [ ] Private subnets cannot accept inbound from internet

- [ ] **OPA Policy Validation**
  - [ ] Run: `conftest test . -p ../opa-policy.rego`
  - [ ] Zero policy violations

## Estimated Monthly Costs (us-east-1)

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| NAT Gateway (per AZ) | 3 | $32.40 | $97.20 |
| NAT Gateway data transfer (1TB) | 3 AZs | $0.045/GB | $45.00 |
| VPC Flow Logs (500GB/month) | 1 | $0.50/GB | $250.00 |
| KMS key | 1 | $1.00 | $1.00 |
| **Total (Real-time logging)** | | | **~$393/month** |
| **Total (S3 archival after 7 days)** | | | **~$160/month** |

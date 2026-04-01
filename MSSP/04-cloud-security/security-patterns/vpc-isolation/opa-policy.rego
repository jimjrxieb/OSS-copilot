package cloud.security.vpc_isolation

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Metadata
metadata := {
  "pattern": "vpc-isolation",
  "version": "1.0.0",
  "description": "Enforces Multi-AZ VPC with public/private subnet isolation",
  "compliance": ["CIS-5.1", "CIS-5.2", "CIS-5.3", "CIS-3.9"]
}

# CIS 5.3: Deny auto-assign public IPs on subnets
deny[msg] {
  resource := input.resource.aws_subnet[name]
  resource.map_public_ip_on_launch == true

  msg := sprintf(
    "❌ CIS 5.3 VIOLATION: Subnet '%s' has auto-assign public IP enabled. This creates uncontrolled public exposure. Set map_public_ip_on_launch=false and use Elastic IPs explicitly.",
    [name]
  )
}

# Pattern Requirement: Minimum 2 availability zones for HA
deny[msg] {
  subnets := [s | s := input.resource.aws_subnet[_]]
  availability_zones := {s.availability_zone | s := subnets[_]}
  count(availability_zones) < 2

  msg := "❌ VPC ISOLATION PATTERN: Minimum 2 availability zones required for high availability. Current deployment uses only 1 AZ."
}

# CIS 3.9: Require VPC Flow Logs
deny[msg] {
  vpc := input.resource.aws_vpc[vpc_name]
  vpc_id := sprintf("aws_vpc.%s.id", [vpc_name])

  not has_flow_logs(vpc_id)

  msg := sprintf(
    "❌ CIS 3.9 VIOLATION: VPC '%s' missing Flow Logs. Flow Logs are required for visibility, threat detection, and incident response.",
    [vpc_name]
  )
}

has_flow_logs(vpc_ref) {
  flow_log := input.resource.aws_flow_log[_]
  flow_log.vpc_id == vpc_ref
}

# CIS 3.7: Require KMS encryption on Flow Logs
deny[msg] {
  log_group := input.resource.aws_cloudwatch_log_group[name]
  contains(log_group.name, "flow-logs")
  not log_group.kms_key_id

  msg := sprintf(
    "❌ CIS 3.7 VIOLATION: CloudWatch Log Group '%s' must use KMS encryption for Flow Logs to protect sensitive network metadata.",
    [name]
  )
}

# Pattern Requirement: NAT Gateway per AZ (not shared)
deny[msg] {
  nat_gateways := [n | n := input.resource.aws_nat_gateway[_]]
  subnets := [s | s := input.resource.aws_subnet[_]; s.tags.Tier == "private"]
  availability_zones := {s.availability_zone | s := subnets[_]}

  count(nat_gateways) < count(availability_zones)

  msg := sprintf(
    "❌ VPC ISOLATION PATTERN (HA): Each availability zone (%d AZs) must have dedicated NAT Gateway for fault isolation. Found only %d NAT Gateway(s). Shared NAT Gateway creates single point of failure.",
    [count(availability_zones), count(nat_gateways)]
  )
}

# CIS 5.4: Ensure default security group denies all traffic
deny[msg] {
  sg := input.resource.aws_default_security_group[_]

  # Check if default SG has any ingress rules
  count(sg.ingress) > 0

  msg := "❌ CIS 5.4 VIOLATION: Default security group must not have any ingress rules. Remove all ingress to force explicit security group creation."
}

deny[msg] {
  sg := input.resource.aws_default_security_group[_]

  # Check if default SG has any egress rules
  count(sg.egress) > 0

  msg := "❌ CIS 5.4 VIOLATION: Default security group must not have any egress rules. Remove all egress to force explicit security group creation."
}

# Pattern Requirement: VPC Flow Logs retention minimum 90 days
warn[msg] {
  log_group := input.resource.aws_cloudwatch_log_group[name]
  contains(log_group.name, "flow-logs")
  log_group.retention_in_days < 90

  msg := sprintf(
    "⚠️  RECOMMENDATION: CloudWatch Log Group '%s' retains logs for %d days. CIS recommends 90+ days for forensic analysis and compliance. Current: %d days.",
    [name, log_group.retention_in_days, log_group.retention_in_days]
  )
}

# Pattern Requirement: DNS hostnames and support enabled
deny[msg] {
  vpc := input.resource.aws_vpc[name]
  vpc.enable_dns_hostnames != true

  msg := sprintf(
    "❌ VPC ISOLATION PATTERN: VPC '%s' must enable DNS hostnames (enable_dns_hostnames=true) for private VPC endpoints and internal service discovery.",
    [name]
  )
}

deny[msg] {
  vpc := input.resource.aws_vpc[name]
  vpc.enable_dns_support != true

  msg := sprintf(
    "❌ VPC ISOLATION PATTERN: VPC '%s' must enable DNS support (enable_dns_support=true) for private VPC endpoints to function.",
    [name]
  )
}

# Pattern Recommendation: Tag resources with security pattern
warn[msg] {
  vpc := input.resource.aws_vpc[name]
  not vpc.tags.SecurityPattern

  msg := sprintf(
    "⚠️  RECOMMENDATION: VPC '%s' should be tagged with SecurityPattern='vpc-isolation' for audit and compliance tracking.",
    [name]
  )
}

# Summary of all violations and warnings
summary := {
  "violations": count(deny),
  "warnings": count(warn),
  "pattern": metadata.pattern,
  "compliance_frameworks": metadata.compliance
}

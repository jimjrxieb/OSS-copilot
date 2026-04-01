# VPC Default Security Group Lockdown
# Fixes: CKV2_AWS_12
# Rank: D (auto-fix)
#
# Usage: Copy into your VPC module. The default SG exists on every VPC —
#        this resource takes ownership and removes all rules.
#
# Required variables: project_name, environment

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # No ingress or egress rules — all traffic blocked on the default SG.
  # This forces all resources to use explicitly defined security groups.

  tags = { Name = "${var.project_name}-${var.environment}-default-sg-restricted" }
}

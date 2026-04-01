# Lambda Hardening — VPC, DLQ, Concurrency, Encryption
# Fixes: CKV_AWS_115, CKV_AWS_116, CKV_AWS_117, CKV_AWS_173
# Rank: D (auto-fix)
#
# Usage: Add these attributes to any aws_lambda_function resource.
#        Copy the SG and DLQ resources into your module.
#
# Required variables: project_name, environment, vpc_id, private_subnets
# Required: KMS key ARN for environment variable encryption

# --- Security Group for Lambda in VPC ---

resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-${var.environment}-lambda-"
  description = "Lambda function security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS to VPC (Secrets Manager, RDS via VPC endpoint)"
  }

  tags = { Name = "${var.project_name}-${var.environment}-lambda-sg" }

  lifecycle { create_before_destroy = true }
}

# --- Dead Letter Queue ---

resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "${var.project_name}-${var.environment}-lambda-dlq"
  message_retention_seconds  = 1209600 # 14 days
  kms_master_key_id          = "alias/aws/sqs"

  tags = { Name = "${var.project_name}-${var.environment}-lambda-dlq" }
}

# --- Add these attributes to aws_lambda_function ---
#
# resource "aws_lambda_function" "example" {
#   # ... existing config ...
#
#   reserved_concurrent_executions = 5           # CKV_AWS_115
#
#   dead_letter_config {                          # CKV_AWS_116
#     target_arn = aws_sqs_queue.lambda_dlq.arn
#   }
#
#   vpc_config {                                  # CKV_AWS_117
#     subnet_ids         = var.private_subnets
#     security_group_ids = [aws_security_group.lambda.id]
#   }
#
#   kms_key_arn = aws_kms_key.secrets.arn         # CKV_AWS_173
# }
#
# Note: Lambda in VPC needs a NAT Gateway or VPC Endpoint to reach
# AWS services (Secrets Manager, RDS). Ensure your VPC has these.

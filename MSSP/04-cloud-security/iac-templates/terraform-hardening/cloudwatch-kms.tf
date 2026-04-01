# CloudWatch Log Group KMS Encryption
# Fixes: CKV_AWS_158
# Rank: D (auto-fix)
#
# Usage: Copy this into any module that creates aws_cloudwatch_log_group resources.
#        Pass the KMS key ARN to each log group via kms_key_id.
#
# Required variables: project_name, environment, aws_region
# Required data source: data.aws_caller_identity.current

resource "aws_kms_key" "cloudwatch" {
  description             = "CloudWatch log group encryption for ${var.project_name}-${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action    = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${var.project_name}-${var.environment}-cloudwatch-kms" }
}

# Example usage:
#
# resource "aws_cloudwatch_log_group" "example" {
#   name              = "/aws/example/${var.project_name}-${var.environment}"
#   retention_in_days = 365
#   kms_key_id        = aws_kms_key.cloudwatch.arn
#
#   tags = { Name = "${var.project_name}-${var.environment}-example-logs" }
# }

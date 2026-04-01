# RDS Hardening — Monitoring, IAM Auth, Query Logging
# Fixes: CKV_AWS_118, CKV_AWS_161, CKV_AWS_226, CKV_AWS_293, CKV2_AWS_30
# Rank: D (auto-fix)
#
# Usage: Add the attributes to your aws_db_instance.
#        Copy the monitoring role and parameter group into your RDS module.
#
# Required variables: project_name, environment

# --- Enhanced Monitoring Role ---

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-${var.environment}-rds-monitoring" }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# --- Parameter Group for Query Logging (pgaudit) ---

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-${var.environment}-postgres15"
  family = "postgres15"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pgaudit.log"
    value = "all"
  }

  tags = { Name = "${var.project_name}-${var.environment}-pg-params" }
}

# --- Add these attributes to aws_db_instance ---
#
# resource "aws_db_instance" "main" {
#   # ... existing config ...
#
#   iam_database_authentication_enabled = true                             # CKV_AWS_161
#   auto_minor_version_upgrade          = true                             # CKV_AWS_226
#   deletion_protection                 = var.environment == "production"  # CKV_AWS_293
#   monitoring_interval                 = 60                               # CKV_AWS_118
#   monitoring_role_arn                 = aws_iam_role.rds_monitoring.arn  # CKV_AWS_118
#   parameter_group_name                = aws_db_parameter_group.postgres.name  # CKV2_AWS_30
# }

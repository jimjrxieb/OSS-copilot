# S3 Access Logging Bucket + Configuration
# Fixes: CKV_AWS_18, CKV_AWS_300
# Rank: D (auto-fix)
#
# Usage: Copy the access logs bucket into your module.
#        Add aws_s3_bucket_logging to each bucket that needs logging.
#        Add abort-incomplete-multipart rule to each lifecycle config.
#
# Required variables: project_name, environment
# Required data source: data.aws_caller_identity.current

resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project_name}-${var.environment}-access-logs-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${var.project_name}-${var.environment}-access-logs" }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "access-log-retention"
    status = "Enabled"
    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Example: wire a bucket to the access log bucket
#
# resource "aws_s3_bucket_logging" "my_bucket" {
#   bucket        = aws_s3_bucket.my_bucket.id
#   target_bucket = aws_s3_bucket.access_logs.id
#   target_prefix = "access-logs/${aws_s3_bucket.my_bucket.id}/"
# }

# Example: add abort-incomplete-multipart to an existing lifecycle config
#
# rule {
#   id     = "abort-incomplete-multipart"
#   status = "Enabled"
#   filter {}
#
#   abort_incomplete_multipart_upload {
#     days_after_initiation = 7
#   }
# }

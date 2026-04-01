# IAM Policy Scoping — Flow Logs
# Fixes: CKV_AWS_355, CKV_AWS_290
# Rank: C (requires knowing the target log group ARN)
#
# Usage: Replace the Resource = "*" in your flow logs IAM policy
#        with the specific log group ARN.

# --- Scoped flow logs policy (replace wildcard) ---
#
# resource "aws_iam_role_policy" "flow_logs" {
#   name = "flow-logs-publish"
#   role = aws_iam_role.flow_logs.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = [
#         "logs:CreateLogGroup",
#         "logs:CreateLogStream",
#         "logs:PutLogEvents",
#         "logs:DescribeLogGroups",
#         "logs:DescribeLogStreams"
#       ]
#       Effect   = "Allow"
#       Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
#     }]
#   })
# }
#
# The key change: Resource = "*" becomes Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
# The :* suffix is required for CloudWatch Logs — it covers log streams within the group.

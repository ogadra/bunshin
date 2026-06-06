# Deliver to CloudWatch Logs rather than S3 to reuse the retention and IAM
# conventions in logs.tf/iam.tf, instead of standing up an S3 bucket and its
# hardening surface (encryption, public-access block, lifecycle) as a log sink.

# A single role serves both regions because IAM is global.
data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "bunshin-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "${aws_cloudwatch_log_group.flow_logs.arn}:*",
      "${aws_cloudwatch_log_group.flow_logs_apne3.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name   = "bunshin-vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

# trivy:ignore:AVD-AWS-0017 -- KMS encryption is not required for this use case
resource "aws_cloudwatch_log_group" "flow_logs" {
  # checkov:skip=CKV_AWS_158:KMS encryption is not required for this use case
  name                        = "/vpc/bunshin-flow-logs"
  retention_in_days           = 365
  deletion_protection_enabled = true

  tags = local.common_tags
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "bunshin"
  })
}

# trivy:ignore:AVD-AWS-0017 -- KMS encryption is not required for this use case
resource "aws_cloudwatch_log_group" "flow_logs_apne3" {
  # checkov:skip=CKV_AWS_158:KMS encryption is not required for this use case
  provider = aws.apne3

  name                        = "/vpc/bunshin-flow-logs"
  retention_in_days           = 365
  deletion_protection_enabled = true

  tags = local.common_tags
}

resource "aws_flow_log" "apne3" {
  provider = aws.apne3

  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs_apne3.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3"
  })
}

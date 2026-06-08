# trivy:ignore:AVD-AWS-0017 -- KMS encryption is not required for this use case
resource "aws_cloudwatch_log_group" "broker" {
  # checkov:skip=CKV_AWS_158:KMS encryption is not required for this use case
  name                        = "/ecs/bunshin-broker"
  retention_in_days           = 365
  deletion_protection_enabled = true

  tags = merge(local.common_tags, {
    Service = "broker"
  })
}

# 他の apne3 リソースは bunshin-apne3-* 命名だが、このテーブルだけは apne1 と
# 同名にする。リージョンが名前空間を分けるため衝突せず、broker をリージョン
# 非依存に保てるため。
#
# trivy:ignore:AVD-AWS-0024 -- PITR is not required for ephemeral runner state
# trivy:ignore:AVD-AWS-0025 -- AWS managed encryption is sufficient for this use case
resource "aws_dynamodb_table" "runners_apne3" {
  # checkov:skip=CKV_AWS_28:PITR is not required for ephemeral runner state
  # checkov:skip=CKV_AWS_119:AWS managed encryption is sufficient for this use case
  provider = aws.apne3

  name         = "bunshin-runners"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "runnerId"

  attribute {
    name = "runnerId"
    type = "S"
  }

  attribute {
    name = "currentSessionId"
    type = "S"
  }

  attribute {
    name = "idleBucket"
    type = "S"
  }

  global_secondary_index {
    name            = "session-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "currentSessionId"
      key_type       = "HASH"
    }
  }

  global_secondary_index {
    name            = "idle-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "idleBucket"
      key_type       = "HASH"
    }
  }

  tags = {
    Project     = "Bunshin"
    Environment = "shared"
    Service     = "broker"
    ManagedBy   = "terraform"
  }
}

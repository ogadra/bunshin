# trivy:ignore:AVD-AWS-0024 -- PITR is not required for ephemeral runner state
# trivy:ignore:AVD-AWS-0025 -- AWS managed encryption is sufficient for this use case
resource "aws_dynamodb_table" "runners_apne3" {
  # checkov:skip=CKV_AWS_28:PITR is not required for ephemeral runner state
  # checkov:skip=CKV_AWS_119:AWS managed encryption is sufficient for this use case
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
    name = "idleShard"
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
      attribute_name = "idleShard"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "runnerId"
      key_type       = "RANGE"
    }
  }

  tags = {
    Project     = "Bunshin"
    Environment = "shared"
    Service     = "broker"
    ManagedBy   = "terraform"
  }
}

# trivy:ignore:AVD-AWS-0089 -- Access logging on an archive bucket would itself generate logs to archive
resource "aws_s3_bucket" "logs" {
  # checkov:skip=CKV_AWS_18:Access logging on an archive bucket would itself generate logs to archive
  # checkov:skip=CKV2_AWS_62:Event notifications are not required for archive storage
  # checkov:skip=CKV_AWS_144:Cross-region replication is not required for archive storage
  # checkov:skip=CKV_AWS_145:SSE-S3 is sufficient for logs already retained in Cloud Logging
  bucket = local.logs_bucket_name

  tags = merge(local.common_tags, {
    Name    = local.logs_bucket_name
    Service = "logs"
  })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# trivy:ignore:AVD-AWS-0132 -- SSE-S3 is sufficient for logs already retained in Cloud Logging
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

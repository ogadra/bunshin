# trivy:ignore:AVD-AWS-0089 -- Access logs are not required for the initial static origin
resource "aws_s3_bucket" "static" {
  # checkov:skip=CKV_AWS_18:Access logs are not required for the initial static origin
  # checkov:skip=CKV_AWS_144:Cross-region replication is not required for initial static assets
  # checkov:skip=CKV2_AWS_61:Lifecycle policy is not required until static deploy retention is defined
  # checkov:skip=CKV2_AWS_62:Event notifications are not required for static asset serving
  # checkov:skip=CKV_AWS_145:AWS managed encryption is sufficient for static assets
  bucket           = format("bunshin-static-%s-%s-an", data.aws_caller_identity.current.account_id, data.aws_region.current.id)
  bucket_namespace = "account-regional"

  tags = merge(local.common_tags, {
    Name    = format("bunshin-static-%s-%s-an", data.aws_caller_identity.current.account_id, data.aws_region.current.id)
    Service = "static"
  })
}

resource "aws_s3_bucket_public_access_block" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# trivy:ignore:AVD-AWS-0132 -- AWS managed encryption is sufficient for static assets
resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.static.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.static.json
}

data "aws_iam_policy_document" "static" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

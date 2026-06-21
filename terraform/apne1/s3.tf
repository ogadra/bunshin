# trivy:ignore:AVD-AWS-0089 -- Access logs are not required until static delivery logging is defined
# trivy:ignore:AVD-AWS-0132 -- AWS managed encryption is sufficient for static assets
resource "aws_s3_bucket" "static" {
  # checkov:skip=CKV_AWS_18:Access logs are not required until static delivery logging is defined
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
      values   = [var.cloudfront_distribution_arn]
    }
  }
}

data "aws_iam_policy_document" "static_replication_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.static.arn]
    }
  }
}

resource "aws_iam_role" "static_replication" {
  name               = "bunshin-apne1-static-replication"
  assume_role_policy = data.aws_iam_policy_document.static_replication_assume_role.json

  tags = merge(local.common_tags, {
    Service = "static"
  })
}

data "aws_iam_policy_document" "static_replication" {
  statement {
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.static.arn]
  }

  statement {
    actions = [
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.static.arn}/*"]
  }

  statement {
    actions = [
      "s3:ReplicateDelete",
      "s3:ReplicateObject",
      "s3:ReplicateTags",
    ]
    resources = ["${var.static_replication_destination_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "static_replication" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name   = "bunshin-apne1-static-replication"
  role   = aws_iam_role.static_replication.id
  policy = data.aws_iam_policy_document.static_replication.json
}

resource "aws_s3_bucket_replication_configuration" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  depends_on = [
    aws_iam_role_policy.static_replication,
    aws_s3_bucket_versioning.static,
  ]

  role   = aws_iam_role.static_replication.arn
  bucket = aws_s3_bucket.static.id

  rule {
    id       = "apne3-static-failover"
    priority = 1
    status   = "Enabled"

    delete_marker_replication {
      status = "Enabled"
    }

    filter {
      prefix = ""
    }

    destination {
      bucket        = var.static_replication_destination_bucket_arn
      storage_class = "STANDARD"
    }
  }

  lifecycle {
    precondition {
      condition     = var.static_replication_destination_bucket_versioning_status == "Enabled"
      error_message = "The static replication destination bucket must have versioning enabled."
    }
  }
}

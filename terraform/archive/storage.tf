# service agentはproject作成時には存在しないため明示的に作る
resource "google_project_service_identity" "logging" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  provider = google-beta

  service = "logging.googleapis.com"
}

# trivy:ignore:AVD-GCP-0066 -- Google-managed encryption is sufficient for logs already retained in Cloud Logging
resource "google_storage_bucket" "logs_export" {
  # checkov:skip=CKV_GCP_62:Access logging on an archive bucket would itself generate logs to archive
  name     = local.logs_export_bucket_name
  location = "ASIA-NORTHEAST1"

  labels = local.common_labels

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 1
    }
  }
}

resource "google_storage_bucket_iam_member" "logs_export_logging_writer" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  bucket = google_storage_bucket.logs_export.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_project_service_identity.logging.email}"
}

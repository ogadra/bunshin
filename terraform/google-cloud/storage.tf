# trivy:ignore:AVD-GCP-0066 -- Google-managed encryption is sufficient for static assets
resource "google_storage_bucket" "static" {
  # checkov:skip=CKV_GCP_62:Access logging is not required until static delivery logging is defined
  name     = format("bunshin-static-%s-asia1", data.google_project.current.project_id)
  location = "ASIA1"
  rpo      = "ASYNC_TURBO"

  labels = local.common_labels

  versioning {
    enabled = true
  }

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 7
    }
  }

  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 1
    }
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  depends_on = [google_project_service.apis["storage.googleapis.com"]]
}

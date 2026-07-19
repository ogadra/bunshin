# trivy:ignore:AVD-GCP-0066 -- Google-managed encryption is sufficient for static assets
resource "google_storage_bucket" "static" {
  # checkov:skip=CKV_GCP_62:Access logging is not required until static delivery logging is defined
  # checkov:skip=CKV_GCP_114:PAP inherited is required to grant allUsers read on the static SPA bucket
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
  public_access_prevention    = "inherited"

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  depends_on = [google_project_service.apis["storage.googleapis.com"]]
}

# Cloud CDN's fill service account is Google-managed and only auto-provisions
# after a successful backfill, so a "private bucket + CDN SA binding" chicken-
# and-egg is unresolvable from Terraform. Serve the bucket publicly and rely
# on CDN as the primary access path; the bucket URL is also readable, which
# is fine for a public SPA.
# trivy:ignore:AVD-GCP-0001 -- allUsers read is intentional for public SPA distribution
resource "google_storage_bucket_iam_member" "static_public_read" {
  # checkov:skip=CKV_GCP_28:allUsers read is intentional for public SPA distribution
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  bucket = google_storage_bucket.static.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

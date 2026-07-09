resource "google_artifact_registry_repository" "bunshin" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV_GCP_84:Google-managed encryption is sufficient
  location      = "asia-northeast2"
  repository_id = "bunshin"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-last-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
}

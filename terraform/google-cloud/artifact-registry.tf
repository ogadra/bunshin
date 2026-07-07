# ECR (last 3 images) と対称の cleanup policy を持つ Docker repository を 2 region に作成する
resource "google_artifact_registry_repository" "bunshin" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV_GCP_84:Google-managed encryption is sufficient
  for_each = toset(["asia-northeast1", "asia-northeast2"])

  location      = each.key
  repository_id = "bunshin"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-last-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }

  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
}

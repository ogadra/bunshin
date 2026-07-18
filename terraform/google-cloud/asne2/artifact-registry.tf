resource "google_artifact_registry_repository" "bunshin" {
  # checkov:skip=CKV_GCP_84:Google-managed encryption is sufficient
  location      = "asia-northeast2"
  repository_id = "bunshin"
  format        = "DOCKER"
  labels        = local.common_labels

  cleanup_policies {
    id     = "keep-last-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
}

# image が未 push のまま apply が Deployment 作成に進むと Pod が ImagePullBackOff で
# rollout 待ちに詰まる。plan 段階で image の存在を確認して落とす
data "google_artifact_registry_docker_image" "deployables" {
  for_each      = toset(["broker", "nginx", "runner"])
  location      = google_artifact_registry_repository.bunshin.location
  repository_id = google_artifact_registry_repository.bunshin.repository_id
  image_name    = "${each.key}:${var.image_tag}"
}

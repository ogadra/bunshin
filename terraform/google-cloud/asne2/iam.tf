data "google_project" "current" {}

resource "google_service_account" "gke_node" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  account_id   = "bunshin-gke-node-asne2"
  display_name = "bunshin GKE node (asne2)"
}

# log / metric / metadata 系は API 側が project scope。resource-level に絞れない
resource "google_project_iam_member" "gke_node" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = data.google_project.current.project_id
  role    = each.value
  member  = google_service_account.gke_node.member
}

# image pull は自 region の repo だけに絞る。blast radius を region に閉じる
resource "google_artifact_registry_repository_iam_member" "gke_node_reader" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  location   = google_artifact_registry_repository.bunshin.location
  repository = google_artifact_registry_repository.bunshin.name
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.gke_node.member
}

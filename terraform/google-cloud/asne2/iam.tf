data "google_client_config" "default" {}

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

  project = data.google_client_config.default.project
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

# workload identity poolはproject-scope(`<PROJECT_ID>.svc.id.goog`)だが、KSA identifierを
# regionごとに分けることでbindingもregionごとに独立させる。member文字列内のKSA参照は
# kubernetes_service_account_v1.brokerのmetadataから取り、KSAとbindingをsingle source of truthに保つ
resource "google_service_account_iam_member" "broker_workload_identity" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  service_account_id = var.broker_service_account_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${data.google_client_config.default.project}.svc.id.goog[${kubernetes_service_account_v1.broker.metadata[0].namespace}/${kubernetes_service_account_v1.broker.metadata[0].name}]"
}

resource "google_service_account" "broker" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  account_id   = "bunshin-broker"
  display_name = "bunshin broker (Workload Identity)"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_project_iam_member" "broker_datastore_user" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  project = data.google_project.current.project_id
  role    = "roles/datastore.user"
  member  = google_service_account.broker.member

  depends_on = [google_project_service.apis["firestore.googleapis.com"]]
}

resource "google_service_account" "gke_node" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  account_id   = "bunshin-gke-node"
  display_name = "bunshin GKE node"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

# GKE node の system daemon (kubelet / logging / monitoring / image pull) に必要な最小権限のみ付与する
resource "google_project_iam_member" "gke_node" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = data.google_project.current.project_id
  role    = each.value
  member  = google_service_account.gke_node.member
}

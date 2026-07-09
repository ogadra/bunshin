resource "google_service_account" "broker" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  account_id   = "bunshin-broker"
  display_name = "bunshin broker (Workload Identity)"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_project_iam_member" "broker_datastore_user" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  project = data.google_project.current.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.broker.email}"

  depends_on = [google_project_service.apis["firestore.googleapis.com"]]
}

# kubectl exec/port-forward を使わない運用のため gatewayAdmin ではなく gatewayEditor を付与
resource "google_project_iam_member" "deploy_gateway_editor" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  project = data.google_project.current.project_id
  role    = "roles/gkehub.gatewayEditor"
  member  = var.deploy_principal

  depends_on = [google_project_service.apis["gkehub.googleapis.com"]]
}

# get-credentials が membership の取得に viewer 権限を要求する
resource "google_project_iam_member" "deploy_gateway_viewer" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  project = data.google_project.current.project_id
  role    = "roles/gkehub.viewer"
  member  = var.deploy_principal

  depends_on = [google_project_service.apis["gkehub.googleapis.com"]]
}

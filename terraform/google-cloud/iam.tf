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

# workload identity pool は project-wide (`<PROJECT_ID>.svc.id.goog`)。同名 KSA (default/broker) を持つ
# asne1 / asne2 の Pod が同一 GSA を impersonate できるため、region ごとに binding を分ける必要はない
resource "google_service_account_iam_member" "broker_workload_identity" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  service_account_id = google_service_account.broker.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${data.google_project.current.project_id}.svc.id.goog[default/broker]"
}


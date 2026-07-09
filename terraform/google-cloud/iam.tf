resource "google_service_account" "broker" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  account_id   = "bunshin-broker"
  display_name = "bunshin broker (Workload Identity)"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

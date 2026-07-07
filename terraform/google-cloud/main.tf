# Connect Gateway 経由の deploy と Firestore / Artifact Registry / Logging 基盤に必要な API を有効化する
resource "google_project_service" "apis" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "connectgateway.googleapis.com",
    "firestore.googleapis.com",
    "gkehub.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
  ])

  project = data.google_project.current.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

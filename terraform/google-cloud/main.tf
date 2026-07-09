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

module "asne1" {
  source = "./asne1"

  providers = {
    google = google.asne1
  }

  depends_on = [google_project_service.apis]
}

module "asne2" {
  source = "./asne2"

  providers = {
    google = google.asne2
  }

  depends_on = [google_project_service.apis]
}

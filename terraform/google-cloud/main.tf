resource "google_project_service" "apis" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "firestore.googleapis.com",
    "gkehub.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
  ])

  project = data.google_project.current.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

module "asne1" {
  source = "./asne1"

  broker_service_account_email = google_service_account.broker.email
  deployer_email               = data.google_client_openid_userinfo.me.email

  providers = {
    google     = google.asne1
    kubernetes = kubernetes.asne1
  }

  depends_on = [google_project_service.apis]
}

module "asne2" {
  source = "./asne2"

  broker_service_account_email = google_service_account.broker.email
  deployer_email               = data.google_client_openid_userinfo.me.email

  providers = {
    google     = google.asne2
    kubernetes = kubernetes.asne2
  }

  depends_on = [google_project_service.apis]
}

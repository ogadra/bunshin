resource "google_dns_policy" "bunshin" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name           = "bunshin-asne2"
  enable_logging = true

  networks {
    network_url = google_compute_network.bunshin.id
  }
}

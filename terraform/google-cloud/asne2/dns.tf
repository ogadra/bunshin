# inbound forwarding は cross-cloud で AWS Route53 Resolver から GCP private zone を引くための入口。
# 実際の Route53 outbound endpoint → GCP inbound の wiring は P5-d #230
resource "google_dns_policy" "bunshin" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name                      = "bunshin-asne2"
  enable_logging            = true
  enable_inbound_forwarding = true

  networks {
    network_url = google_compute_network.bunshin.id
  }
}

# private zone は自 region の service host を持つ。両 region の VPC に visibility bind し、
# asne1 ↔ asne2 の fallback を DNS で解決できるようにする (AWS 側 region 別 private zone を両 VPC に
# 関連付けているのと対称)
resource "google_dns_managed_zone" "internal" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name        = "bunshin-internal-${local.region}"
  dns_name    = "${local.region}.${var.domain_name}."
  description = "bunshin internal private zone for ${local.region}"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.bunshin.id
    }
    networks {
      network_url = var.peer_vpc_network
    }
  }
}

resource "google_dns_record_set" "internal_apex" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name         = google_dns_managed_zone.internal.dns_name
  managed_zone = google_dns_managed_zone.internal.name
  type         = "A"
  ttl          = 60

  rrdatas = [google_compute_address.internal_lb.address]
}

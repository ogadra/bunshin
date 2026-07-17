resource "google_certificate_manager_dns_authorization" "apex" {
  name        = "bunshin-apex"
  description = "DNS authorization for Google-managed cert on apex domain"
  domain      = var.domain_name

  labels = local.common_labels

  depends_on = [google_project_service.apis["certificatemanager.googleapis.com"]]
}

resource "google_certificate_manager_certificate" "apex" {
  name        = "bunshin-apex"
  description = "Google-managed cert for apex domain, served via Global External ALB"
  scope       = "DEFAULT"

  managed {
    domains = [var.domain_name]
    dns_authorizations = [
      google_certificate_manager_dns_authorization.apex.id,
    ]
  }

  labels = local.common_labels
}

# ssl_certificates直付けはCertificate Manager certには不可なため、target_https_proxyの
# certificate_mapを介してattachする経路をここで用意する
resource "google_certificate_manager_certificate_map" "apex" {
  name        = "bunshin-apex"
  description = "Certificate map bound to Global External ALB target_https_proxy"

  labels = local.common_labels
}

resource "google_certificate_manager_certificate_map_entry" "apex" {
  name         = "bunshin-apex"
  description  = "Serve apex cert for SNI-matched requests to apex hostname"
  map          = google_certificate_manager_certificate_map.apex.name
  certificates = [google_certificate_manager_certificate.apex.id]
  hostname     = var.domain_name

  labels = local.common_labels
}

resource "google_certificate_manager_dns_authorization" "internal" {
  name     = "bunshin-internal-${local.region}"
  location = local.region
  domain   = "${local.region}.${var.domain_name}"
  labels   = local.common_labels
}

resource "google_certificate_manager_certificate" "internal" {
  name     = "bunshin-internal-${local.region}"
  location = local.region
  labels   = local.common_labels

  managed {
    domains            = ["${local.region}.${var.domain_name}"]
    dns_authorizations = [google_certificate_manager_dns_authorization.internal.id]
  }
}

# GKE Gateway (`gke-l7-rilb`) は annotation `networking.gke.io/certmap` で Certificate Manager の
# cert map を attach する。cert map は API 上 global (regional / global cert の両方を entry に持てる) で、
# cert 本体だけを regional に閉じる
resource "google_certificate_manager_certificate_map" "internal" {
  name   = "bunshin-internal-${local.region}"
  labels = local.common_labels
}

resource "google_certificate_manager_certificate_map_entry" "internal" {
  name         = "bunshin-internal-${local.region}"
  map          = google_certificate_manager_certificate_map.internal.name
  hostname     = "${local.region}.${var.domain_name}"
  certificates = [google_certificate_manager_certificate.internal.id]
  labels       = local.common_labels
}

resource "kubernetes_manifest" "internal_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "bunshin-internal"
      namespace = "default"
      annotations = {
        "networking.gke.io/certmap" = google_certificate_manager_certificate_map.internal.name
      }
    }
    spec = {
      gatewayClassName = "gke-l7-rilb"
      listeners = [{
        name     = "https"
        port     = 443
        protocol = "HTTPS"
        allowedRoutes = {
          namespaces = { from = "Same" }
        }
      }]
    }
  }
}

resource "kubernetes_manifest" "internal_httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "bunshin-internal-nginx"
      namespace = "default"
    }
    spec = {
      parentRefs = [{
        name = "bunshin-internal"
      }]
      rules = [{
        backendRefs = [{
          name = kubernetes_service_v1.nginx.metadata[0].name
          port = local.service_ports.nginx
        }]
      }]
    }
  }
}

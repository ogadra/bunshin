resource "google_certificate_manager_dns_authorization" "internal" {
  name     = local.internal_lb_name
  location = local.region
  domain   = local.internal_lb_hostname
  labels   = local.common_labels
}

resource "google_certificate_manager_certificate" "internal" {
  name     = local.internal_lb_name
  location = local.region
  labels   = local.common_labels

  managed {
    domains            = [local.internal_lb_hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.internal.id]
  }
}

# GKE Gateway(`gke-l7-rilb`)はannotation `networking.gke.io/certmap`でCertificate Managerの
# cert mapをattachする。cert mapはAPI上global(regional / global certの両方をentryに持てる)で、
# cert本体だけをregionalに閉じる
resource "google_certificate_manager_certificate_map" "internal" {
  name   = local.internal_lb_name
  labels = local.common_labels
}

resource "google_certificate_manager_certificate_map_entry" "internal" {
  name         = local.internal_lb_name
  map          = google_certificate_manager_certificate_map.internal.name
  hostname     = local.internal_lb_hostname
  certificates = [google_certificate_manager_certificate.internal.id]
  labels       = local.common_labels
}

# Gatewayのdynamic IPは再作成でVIPが変わりDNSを壊す
resource "google_compute_address" "internal_lb" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name         = local.internal_lb_name
  region       = local.region
  subnetwork   = google_compute_subnetwork.workload.id
  address_type = "INTERNAL"
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
      addresses = [{
        type  = "NamedAddress"
        value = google_compute_address.internal_lb.name
      }]
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

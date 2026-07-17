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

# Gatewayのdynamic IPは再作成でVIPが変わりDNSを壊す
resource "google_compute_address" "internal_lb" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name         = local.internal_lb_name
  region       = local.region
  subnetwork   = google_compute_subnetwork.workload.id
  address_type = "INTERNAL"
}

# gke-l7-rilb は annotation `networking.gke.io/certmap` を未サポート。regional Gateway では
# listenerの`tls.options`に`networking.gke.io/cert-manager-certs`を指定してRegional Certificate
# を直接参照する
resource "kubernetes_manifest" "internal_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "bunshin-internal"
      namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
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
        tls = {
          mode = "Terminate"
          options = {
            "networking.gke.io/cert-manager-certs" = google_certificate_manager_certificate.internal.name
          }
        }
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
      namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
    }
    spec = {
      parentRefs = [{
        name = "bunshin-internal"
      }]
      rules = [{
        backendRefs = [{
          name      = kubernetes_service_v1.nginx.metadata[0].name
          namespace = kubernetes_service_v1.nginx.metadata[0].namespace
          port      = local.service_ports.nginx
        }]
      }]
    }
  }
}

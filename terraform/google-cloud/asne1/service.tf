resource "kubernetes_service_v1" "broker" {
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see serviceaccount.tf header
  metadata {
    name      = "broker"
    namespace = "default"
    labels    = { app = "broker" }
  }
  spec {
    type     = "ClusterIP"
    selector = { app = "broker" }
    port {
      name        = "http"
      port        = local.service_ports.broker
      target_port = local.service_ports.broker
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service_v1" "runner" {
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see serviceaccount.tf header
  metadata {
    name      = "runner"
    namespace = "default"
    labels    = { app = "runner" }
  }
  spec {
    type     = "ClusterIP"
    selector = { app = "runner" }
    port {
      name        = "http"
      port        = local.service_ports.runner
      target_port = local.service_ports.runner
      protocol    = "TCP"
    }
  }
}

# nginx Service に付ける cloud.google.com/neg annotation で、GKE NEG controller が region 単位の
# standalone zonal NEG を作る。Global LB (P4-j #223) の backend service がここを data で参照する
resource "kubernetes_service_v1" "nginx" {
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see serviceaccount.tf header
  metadata {
    name      = "nginx"
    namespace = "default"
    labels    = { app = "nginx" }
    annotations = {
      "cloud.google.com/neg" = jsonencode({
        exposed_ports = {
          "${local.service_ports.nginx}" = {
            name = "bunshin-nginx-${local.region}"
          }
        }
      })
    }
  }
  spec {
    type     = "ClusterIP"
    selector = { app = "nginx" }
    port {
      name        = "http"
      port        = local.service_ports.nginx
      target_port = local.service_ports.nginx
      protocol    = "TCP"
    }
  }
}

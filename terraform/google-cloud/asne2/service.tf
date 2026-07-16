resource "kubernetes_service_v1" "broker" {
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
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
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
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

# nginx Serviceに付けるcloud.google.com/neg annotationで、GKE NEG controllerがregionごとの
# standalone zonal NEGを作る。Global LBのbackend serviceがこれをdata経由で参照する
resource "kubernetes_service_v1" "nginx" {
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
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

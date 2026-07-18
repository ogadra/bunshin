resource "kubernetes_service_v1" "broker" {
  metadata {
    name      = "broker"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
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
  metadata {
    name      = "runner"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
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

# cloud.google.com/neg annotationでGKE NEG controllerがregionごとのstandalone zonal NEGを作る。
# Global LBのbackend serviceはこのNEG群をmodule outputs経由で参照する
resource "kubernetes_service_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
    labels    = { app = "nginx" }
    annotations = {
      "cloud.google.com/neg" = jsonencode({
        exposed_ports = {
          "${local.service_ports.nginx}" = {
            name = local.nginx_neg_name
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

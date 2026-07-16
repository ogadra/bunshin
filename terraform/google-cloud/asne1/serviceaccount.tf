resource "kubernetes_service_account_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
    labels    = { app = "nginx" }
  }
}

resource "kubernetes_service_account_v1" "runner" {
  metadata {
    name      = "runner"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
    labels    = { app = "runner" }
  }
}

# broker PodはWorkload IdentityでFirestoreに触るためGSA impersonationをannotationで宣言する。
# KSA名はregionごとに一意化し、workload identity poolの同一プール内でasne1 / asne2のbindingを分離する
resource "kubernetes_service_account_v1" "broker" {
  metadata {
    name      = "broker-asne1"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
    labels    = { app = "broker" }
    annotations = {
      "iam.gke.io/gcp-service-account" = var.broker_service_account_email
    }
  }
}

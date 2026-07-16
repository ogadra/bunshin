# default namespaceは暫定。CKV_K8S_21の指摘通り本来は専用namespaceに置くべきだが、
# namespace分離は後続PRで対応するため、それまでは全KSA / Serviceでskipする
resource "kubernetes_service_account_v1" "nginx" {
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
  metadata {
    name      = "nginx"
    namespace = "default"
    labels    = { app = "nginx" }
  }
}

resource "kubernetes_service_account_v1" "runner" {
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
  metadata {
    name      = "runner"
    namespace = "default"
    labels    = { app = "runner" }
  }
}

# broker PodはWorkload IdentityでFirestoreに触るためGSA impersonationをannotationで宣言する。
# KSA名はregionごとに一意化し、workload identity poolの同一プール内でasne1 / asne2のbindingを分離する
resource "kubernetes_service_account_v1" "broker" {
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
  metadata {
    name      = "broker-asne2"
    namespace = "default"
    labels    = { app = "broker" }
    annotations = {
      "iam.gke.io/gcp-service-account" = var.broker_service_account_email
    }
  }
}

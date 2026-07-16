# default namespace は暫定。CKV_K8S_21 の指摘通り本来は専用 namespace に置くべきだが、
# namespace 分離は後続 PR で対応するため、それまでは全 KSA / Service で skip する
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

# broker Pod は Workload Identity で Firestore に触るため GSA impersonation を annotation で宣言する。
# KSA 名は region ごとに一意化し、workload identity pool の同一プール内で asne1 / asne2 の binding を分離する
resource "kubernetes_service_account_v1" "broker" {
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
  metadata {
    name      = "broker-asne1"
    namespace = "default"
    labels    = { app = "broker" }
    annotations = {
      "iam.gke.io/gcp-service-account" = var.broker_service_account_email
    }
  }
}

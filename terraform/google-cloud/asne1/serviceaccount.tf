# default namespace は broker Workload Identity binding (`[default/broker]`) と ECS 側 flat な CloudMap
# namespace (`broker.internal`) の対称性を保つための設計選択のため、CKV_K8S_21 は全 KSA / Service で許容する
resource "kubernetes_service_account_v1" "nginx" {
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see file header
  metadata {
    name      = "nginx"
    namespace = "default"
    labels    = { app = "nginx" }
  }
}

resource "kubernetes_service_account_v1" "runner" {
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see file header
  metadata {
    name      = "runner"
    namespace = "default"
    labels    = { app = "runner" }
  }
}

# broker Pod は Workload Identity で Firestore に触るため GSA impersonation を annotation で宣言する
resource "kubernetes_service_account_v1" "broker" {
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see file header
  metadata {
    name      = "broker"
    namespace = "default"
    labels    = { app = "broker" }
    annotations = {
      "iam.gke.io/gcp-service-account" = var.broker_service_account_email
    }
  }
}

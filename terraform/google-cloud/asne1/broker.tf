# Autopilotがsecurityとresource設定をinjectするため、Deployment側は最小限だけ書く
resource "kubernetes_deployment_v1" "broker" {
  # checkov:skip=CKV_K8S_8:Liveness probe wiring is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_9:Readiness probe wiring is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_10:Autopilot injects CPU requests
  # checkov:skip=CKV_K8S_11:Autopilot injects CPU limits
  # checkov:skip=CKV_K8S_12:Autopilot injects memory limits
  # checkov:skip=CKV_K8S_13:Autopilot injects memory requests
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_28:Autopilot blocks NET_RAW and other elevated capabilities
  # checkov:skip=CKV_K8S_29:Autopilot enforces baseline pod-level securityContext
  # checkov:skip=CKV_K8S_30:Autopilot enforces baseline container-level securityContext
  # checkov:skip=CKV_K8S_43:image_tag is a git SHA (immutable); digest form is redundant
  metadata {
    name      = "broker"
    namespace = "default"
    labels    = { app = "broker" }
  }

  spec {
    replicas = var.desired_counts.broker
    selector {
      match_labels = { app = "broker" }
    }
    template {
      metadata {
        labels = { app = "broker" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.broker.metadata[0].name

        container {
          name  = "broker"
          image = "${local.image_registry}/broker:${var.image_tag}"

          port {
            container_port = local.service_ports.broker
            protocol       = "TCP"
          }

          env {
            name  = "STACK_NAME"
            value = local.region
          }
          env {
            name  = "BUNSHIN_STORE"
            value = "firestore"
          }
          env {
            name  = "BUNSHIN_STACKS"
            value = join(",", var.bunshin_stacks)
          }
          env {
            name  = "GOOGLE_CLOUD_PROJECT"
            value = data.google_project.current.project_id
          }
          env {
            name  = "FIRESTORE_DATABASE"
            value = google_firestore_database.runners.name
          }
        }
      }
    }
  }
}

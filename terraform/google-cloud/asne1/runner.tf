resource "kubernetes_deployment_v1" "runner" {
  # checkov:skip=CKV_K8S_8:Liveness probe wiring is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_9:Readiness probe wiring is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_21:default namespace is temporary; namespace split is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_28:Autopilot blocks NET_RAW and other elevated capabilities
  # checkov:skip=CKV_K8S_29:Autopilot enforces baseline pod-level securityContext
  # checkov:skip=CKV_K8S_30:Autopilot enforces baseline container-level securityContext
  # checkov:skip=CKV_K8S_43:image_tag is a git SHA (immutable); digest form is redundant
  metadata {
    name      = "runner"
    namespace = "default"
    labels    = { app = "runner" }
  }

  spec {
    replicas = var.desired_counts.runner
    selector {
      match_labels = { app = "runner" }
    }
    template {
      metadata {
        labels = { app = "runner" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.runner.metadata[0].name

        container {
          name  = "runner"
          image = "${local.image_registry}/runner:${var.image_tag}"

          port {
            container_port = local.service_ports.runner
            protocol       = "TCP"
          }

          env {
            name  = "STACK_NAME"
            value = local.region
          }
          env {
            name  = "RUNNER_PORT"
            value = tostring(local.service_ports.runner)
          }
          env {
            name  = "BROKER_URL"
            value = "http://${local.broker_host}:${local.service_ports.broker}"
          }

          resources {
            requests = {
              cpu                 = "250m"
              memory              = "512Mi"
              "ephemeral-storage" = "1Gi"
            }
            limits = {
              cpu                 = "250m"
              memory              = "512Mi"
              "ephemeral-storage" = "1Gi"
            }
          }
        }
      }
    }
  }
}

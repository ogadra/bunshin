resource "kubernetes_deployment_v1" "nginx" {
  # checkov:skip=CKV_K8S_8:Liveness probe wiring is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_9:Readiness probe wiring is deferred to a follow-up PR
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_28:Autopilot blocks NET_RAW and other elevated capabilities
  # checkov:skip=CKV_K8S_29:Autopilot enforces baseline pod-level securityContext
  # checkov:skip=CKV_K8S_30:Autopilot enforces baseline container-level securityContext
  # checkov:skip=CKV_K8S_43:image_tag is a git SHA (immutable); digest form is redundant
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
    labels    = { app = "nginx" }
  }

  spec {
    replicas = var.desired_counts.nginx
    selector {
      match_labels = { app = "nginx" }
    }
    template {
      metadata {
        labels = { app = "nginx" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.nginx.metadata[0].name

        container {
          name  = "nginx"
          image = "${local.image_registry}/nginx:${var.image_tag}"

          port {
            container_port = local.service_ports.nginx
            protocol       = "TCP"
          }

          env {
            name  = "STACK_NAME"
            value = local.region
          }
          env {
            name  = "INTERNAL_DOMAIN"
            value = var.domain_name
          }
          env {
            name  = "BUNSHIN_STACKS"
            value = join(",", var.bunshin_stacks)
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

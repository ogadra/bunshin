# Autopilotがsecurity context / capability drop / resource injection / probeデフォルトを強制するため、
# Deployment側で明示していない項目はcluster-level policyで担保される。image tagはgit SHA (immutable)
# のためImagePullPolicy=Alwaysやdigest指定は不要。probeは#221スコープ外で後続で追加する
resource "kubernetes_deployment_v1" "nginx" {
  # checkov:skip=CKV_K8S_8:Liveness probe is out of scope for #221; nginx exposes /health for future wiring
  # checkov:skip=CKV_K8S_9:Readiness probe is out of scope for #221; nginx exposes /health for future wiring
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
    name      = "nginx"
    namespace = "default"
    labels    = { app = "nginx" }
  }

  spec {
    replicas = var.nginx_desired_count
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
        }
      }
    }
  }
}

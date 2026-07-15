# Autopilot は securityContext / capability drop / resource injection / probe defaults を強制するため、
# Deployment 側で明示していない項目は cluster-level policy で担保される。image tag は git SHA
# (immutable) のため ImagePullPolicy=Always や digest 指定は不要。probe は #221 スコープ外で後続で追加する
resource "kubernetes_deployment_v1" "nginx" {
  # checkov:skip=CKV_K8S_8:Liveness probe is out of scope for #221; nginx exposes /health for future wiring
  # checkov:skip=CKV_K8S_9:Readiness probe is out of scope for #221; nginx exposes /health for future wiring
  # checkov:skip=CKV_K8S_10:Autopilot injects CPU requests
  # checkov:skip=CKV_K8S_11:Autopilot injects CPU limits
  # checkov:skip=CKV_K8S_12:Autopilot injects memory limits
  # checkov:skip=CKV_K8S_13:Autopilot injects memory requests
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see serviceaccount.tf header
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
    replicas = 2
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

resource "kubernetes_deployment_v1" "broker" {
  # checkov:skip=CKV_K8S_8:Liveness probe is out of scope for #221
  # checkov:skip=CKV_K8S_9:Readiness probe is out of scope for #221
  # checkov:skip=CKV_K8S_10:Autopilot injects CPU requests
  # checkov:skip=CKV_K8S_11:Autopilot injects CPU limits
  # checkov:skip=CKV_K8S_12:Autopilot injects memory limits
  # checkov:skip=CKV_K8S_13:Autopilot injects memory requests
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see serviceaccount.tf header
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
    replicas = 2
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

resource "kubernetes_deployment_v1" "runner" {
  # checkov:skip=CKV_K8S_8:Liveness probe is out of scope for #221
  # checkov:skip=CKV_K8S_9:Readiness probe is out of scope for #221
  # checkov:skip=CKV_K8S_10:Autopilot injects CPU requests
  # checkov:skip=CKV_K8S_11:Autopilot injects CPU limits
  # checkov:skip=CKV_K8S_12:Autopilot injects memory limits
  # checkov:skip=CKV_K8S_13:Autopilot injects memory requests
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_21:default namespace is intentional; see serviceaccount.tf header
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
    replicas = var.runner_desired_count
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
              "ephemeral-storage" = "1Gi"
            }
            limits = {
              "ephemeral-storage" = "1Gi"
            }
          }
        }
      }
    }
  }
}

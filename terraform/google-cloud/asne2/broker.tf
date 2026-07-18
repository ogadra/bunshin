resource "kubernetes_deployment_v1" "broker" {
  # checkov:skip=CKV_K8S_15:image_tag is a git SHA (immutable); Always is redundant
  # checkov:skip=CKV_K8S_28:Autopilot blocks NET_RAW and other elevated capabilities
  # checkov:skip=CKV_K8S_29:Autopilot enforces baseline pod-level securityContext
  # checkov:skip=CKV_K8S_30:Autopilot enforces baseline container-level securityContext
  # checkov:skip=CKV_K8S_43:image_tag is a git SHA (immutable); digest form is redundant

  # KSA参照だけではWorkload Identity bindingの反映を待たず、Pod起動時にFirestore認証が
  # 失敗しうる。GSA側のIAM binding完了までDeploymentを保留する
  depends_on = [
    google_service_account_iam_member.broker_workload_identity,
    data.google_artifact_registry_docker_image.deployables["broker"],
  ]

  metadata {
    name      = "broker"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
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

          liveness_probe {
            http_get {
              path = "/health"
              port = local.service_ports.broker
            }
            initial_delay_seconds = 5
            period_seconds        = 3
            timeout_seconds       = 1
            failure_threshold     = 2
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = local.service_ports.broker
            }
            initial_delay_seconds = 0
            period_seconds        = 2
            timeout_seconds       = 1
            failure_threshold     = 1
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
            value = data.google_client_config.default.project
          }
          env {
            name  = "FIRESTORE_DATABASE"
            value = google_firestore_database.runners.name
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

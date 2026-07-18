resource "kubernetes_network_policy_v1" "runner_egress" {
  metadata {
    name      = "runner-egress"
    namespace = kubernetes_namespace_v1.bunshin.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = { app = "runner" }
    }
    policy_types = ["Egress"]

    egress {
      to {
        pod_selector {
          match_labels = { app = "broker" }
        }
      }
      ports {
        port     = local.service_ports.broker
        protocol = "TCP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
        pod_selector {
          match_labels = { "k8s-app" = "kube-dns" }
        }
      }
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }
  }
}

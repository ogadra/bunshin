# trivy:ignore:AVD-GCP-0061 -- IP endpoints are disabled entirely; master authorized networks does not apply
# trivy:ignore:AVD-GCP-0050 -- node_config.service_account references google_service_account.gke_node.email (managed in iam.tf); trivy cannot statically resolve provider-computed attributes
resource "google_container_cluster" "bunshin" {
  # checkov:skip=CKV_GCP_12:NetworkPolicy is enforced by Dataplane V2 on Autopilot; explicit network_policy block is not settable
  # checkov:skip=CKV_GCP_20:IP endpoints are disabled entirely; master authorized networks does not apply
  # checkov:skip=CKV_GCP_61:VPC Flow Logs are enabled on the workload subnet in P4-b; intranode visibility is managed by Autopilot and cannot be set explicitly
  # checkov:skip=CKV_GCP_65:RBAC binds Google identities directly (P4-h); Google Groups is optional and not adopted
  # checkov:skip=CKV_GCP_66:Binary Authorization is out of scope; image trust is managed via Artifact Registry lifecycle
  # checkov:skip=CKV_GCP_69:Autopilot enables the Workload Identity metadata server by default
  name             = "bunshin-asne2"
  location         = local.region
  enable_autopilot = true

  network    = google_compute_network.bunshin.id
  subnetwork = google_compute_subnetwork.workload.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "STABLE"
  }

  private_cluster_config {
    enable_private_nodes = true
  }

  # deploy / kubectl / kubernetes provider は fleet 登録 + Connect Gateway 経由。GKE は IP / DNS の
  # 少なくとも一方を control plane endpoint として要求するため、attack surface が広い IP endpoint を
  # 塞ぎ、Google API + IAM で認可される DNS endpoint 側だけを残す
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
    ip_endpoints_config {
      enabled = false
    }
  }

  # Autopilot は monitoring 必須で enable_components 未指定だと API が reject する。既存の VPC Flow
  # Logs / Cloud DNS query log では L7 egress が見えないため advanced_datapath_observability も有効化
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
      "CADVISOR",
      "KUBELET",
    ]
    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = true
    }
  }

  # Autopilot 側で他の node_config 属性は管理される。SA / scope / Shielded Node / metadata server 隔離だけを明示する
  node_config {
    service_account = google_service_account.gke_node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  resource_labels = local.common_labels

  deletion_protection = false
}

resource "google_gke_hub_membership" "bunshin" {
  membership_id = "bunshin-asne2"

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.bunshin.id}"
    }
  }

  labels = local.common_labels
}

# fleet membership が READY を返しても Connect Gateway の routing 反映は数分遅れる。gcloud で
# 状態を待った上で固定 buffer を積み、初回 apply で kubernetes/kubectl 系の POST が 404 で
# 落ちる window を潰す
resource "terraform_data" "cluster_ready" {
  triggers_replace = [google_gke_hub_membership.bunshin.id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      for i in $(seq 1 60); do
        state="$(gcloud container fleet memberships describe ${google_gke_hub_membership.bunshin.membership_id} \
          --location=global --format='value(state.code)' 2>/dev/null || true)"
        if [ "$state" = "READY" ]; then
          sleep 60
          exit 0
        fi
        sleep 10
      done
      echo "fleet membership ${google_gke_hub_membership.bunshin.membership_id} did not become READY within 600s" >&2
      exit 1
    EOT
  }
}

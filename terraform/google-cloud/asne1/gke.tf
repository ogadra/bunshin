# trivy:ignore:AVD-GCP-0061 -- IP endpoints are disabled entirely; master authorized networks does not apply
# trivy:ignore:AVD-GCP-0050 -- Application access flows through Workload Identity per-pod GSAs; a hardened node SA is scheduled as a follow-up
resource "google_container_cluster" "bunshin" {
  # checkov:skip=CKV_GCP_12:NetworkPolicy is enforced by Dataplane V2 on Autopilot; explicit network_policy block is not settable
  # checkov:skip=CKV_GCP_13:Autopilot disables client certificate authentication by default
  # checkov:skip=CKV_GCP_20:IP endpoints are disabled entirely; master authorized networks does not apply
  # checkov:skip=CKV_GCP_65:RBAC binds Google identities directly (P4-h); Google Groups is optional and not adopted
  # checkov:skip=CKV_GCP_66:Binary Authorization is out of scope; image trust is managed via Artifact Registry lifecycle
  # checkov:skip=CKV_GCP_69:Autopilot enables the Workload Identity metadata server by default
  name             = "bunshin-asne1"
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

  # inbound endpoint を全無効化。deploy / kubectl / kubernetes provider はすべて fleet 登録 + Connect Gateway 経由
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = false
    }
    ip_endpoints_config {
      enabled = false
    }
  }

  # Dataplane V2 Observability。VPC Flow Logs (L3/4) + Cloud DNS query log (domain) の上位で Pod L7 egress を可視化する
  monitoring_config {
    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = true
    }
  }

  # 同一 node 内の Pod-to-Pod 通信も VPC を経由させ、subnetwork flow log の対象に含める
  enable_intranode_visibility = true

  resource_labels = local.common_labels

  deletion_protection = false
}

resource "google_gke_hub_membership" "bunshin" {
  membership_id = "bunshin-asne1"

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.bunshin.id}"
    }
  }

  labels = local.common_labels
}

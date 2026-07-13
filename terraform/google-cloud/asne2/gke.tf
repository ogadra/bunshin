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

# trivy:ignore:AVD-GCP-0074 -- Broad port range is the intent of a catchall deny rule
resource "google_compute_firewall" "deny_all_ingress" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name      = "bunshin-asne1-deny-all-ingress"
  network   = google_compute_network.bunshin.name
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# proxy-only subnet の Envoy から workload Pod への到達と、Google LB health check の到達を許可する。
# priority < 65534 でないと deny_all_ingress が勝ってしまうため 1000 を指定。ports は Service target port
# に絞る (nginx / broker=8080, runner=3000)。health check source range は Google が公開している固定値
resource "google_compute_firewall" "allow_proxy_and_healthcheck" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name      = "bunshin-asne1-allow-proxy-and-healthcheck"
  network   = google_compute_network.bunshin.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports = [
      tostring(local.service_ports.nginx),
      tostring(local.service_ports.broker),
      tostring(local.service_ports.runner),
    ]
  }

  source_ranges = [
    local.proxy_only_subnet_cidr,
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

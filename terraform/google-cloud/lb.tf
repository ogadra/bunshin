locals {
  # Autopilotが常に3-zone spreadで配置するため、NEG lookup zoneをrootで固定する。
  # regionalなdata.google_compute_zonesを使うと未使用zoneまで含みNEG unresolveでplanが落ちる
  nginx_neg_zones = {
    "asia-northeast1" = ["asia-northeast1-a", "asia-northeast1-b", "asia-northeast1-c"]
    "asia-northeast2" = ["asia-northeast2-a", "asia-northeast2-b", "asia-northeast2-c"]
  }
}

data "google_compute_network_endpoint_group" "nginx_asne1" {
  provider = google.asne1
  for_each = toset(local.nginx_neg_zones["asia-northeast1"])
  name     = "bunshin-nginx-asia-northeast1"
  zone     = each.value
}

data "google_compute_network_endpoint_group" "nginx_asne2" {
  provider = google.asne2
  for_each = toset(local.nginx_neg_zones["asia-northeast2"])
  name     = "bunshin-nginx-asia-northeast2"
  zone     = each.value
}

resource "google_compute_health_check" "nginx" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name                = "bunshin-nginx"
  check_interval_sec  = 5
  timeout_sec         = 2
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 8080
    request_path = "/health"
  }
}

# `/api/execute` (runner) が SSE stream を返し chunked response で cache 不可なため、
# nginx を挟む `/api/*` 全体を CDN 対象外にする。CDN は backend bucket 側で有効化する
resource "google_compute_backend_service" "nginx" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name                  = "bunshin-nginx"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  session_affinity      = "CLIENT_IP"
  timeout_sec           = 30
  enable_cdn            = false

  health_checks = [google_compute_health_check.nginx.id]

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  dynamic "backend" {
    for_each = merge(
      { for z, neg in data.google_compute_network_endpoint_group.nginx_asne1 : z => neg.id },
      { for z, neg in data.google_compute_network_endpoint_group.nginx_asne2 : z => neg.id },
    )
    content {
      group                 = backend.value
      balancing_mode        = "RATE"
      max_rate_per_endpoint = 100
      capacity_scaler       = 1.0
    }
  }
}

# cdn PR で default_service を backend_bucket に切り替え、`/api/*` の path_matcher を
# backend_service に向ける。この段階では全 request を nginx に流す最小構成に留める
resource "google_compute_url_map" "external" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name            = "bunshin-external"
  default_service = google_compute_backend_service.nginx.id
}

resource "google_compute_target_https_proxy" "external" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name            = "bunshin-external"
  url_map         = google_compute_url_map.external.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.apex.id}"
}

resource "google_compute_global_address" "external_ipv4" {
  name       = "bunshin-external-ipv4"
  ip_version = "IPV4"

  labels = local.common_labels
}

resource "google_compute_global_address" "external_ipv6" {
  name       = "bunshin-external-ipv6"
  ip_version = "IPV6"

  labels = local.common_labels
}

resource "google_compute_global_forwarding_rule" "external_ipv4" {
  name                  = "bunshin-external-ipv4"
  ip_address            = google_compute_global_address.external_ipv4.id
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.external.id
  load_balancing_scheme = "EXTERNAL_MANAGED"

  labels = local.common_labels
}

resource "google_compute_global_forwarding_rule" "external_ipv6" {
  name                  = "bunshin-external-ipv6"
  ip_address            = google_compute_global_address.external_ipv6.id
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.external.id
  load_balancing_scheme = "EXTERNAL_MANAGED"

  labels = local.common_labels
}

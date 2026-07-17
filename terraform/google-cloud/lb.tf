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

# /api/execute (runner)がSSE streamを返しchunked responseでcache不可なため、nginxを挟む/api/*
# 全体をCDN対象外にする。CDNはbackend bucket側で有効化する
resource "google_compute_backend_service" "nginx" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name                  = "bunshin-nginx"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  enable_cdn            = false

  # broker sessionIdはstackスコープのDynamoDB/Firestoreに保存され、他stackへの解決はrunner fallback
  # 経路 (VPC Peering / HA VPN) を通る。CLIENT_IPで同一clientを近regionに固着させ、cross-stack転送を
  # 減らす。AWS Global Acceleratorのclient_affinity=SOURCE_IPと対称
  session_affinity = "CLIENT_IP"

  security_policy      = google_compute_security_policy.backend.id
  edge_security_policy = google_compute_security_policy.edge.id

  health_checks = [google_compute_health_check.nginx.id]

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  dynamic "backend" {
    for_each = toset(concat(module.asne1.nginx_neg_ids, module.asne2.nginx_neg_ids))
    content {
      group                 = backend.value
      balancing_mode        = "RATE"
      max_rate_per_endpoint = 100
      capacity_scaler       = 1.0
    }
  }
}

resource "google_compute_url_map" "external" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name            = "bunshin-external"
  default_service = google_compute_backend_bucket.static.id

  host_rule {
    hosts        = [var.domain_name]
    path_matcher = "main"
  }

  path_matcher {
    name            = "main"
    default_service = google_compute_backend_bucket.static.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.nginx.id
    }
  }
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

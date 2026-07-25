# Cert Manager は managed cert の domain を in-place 更新できない。
# name を local.internal_lb_name から意図的にずらしている。
# これにより domain 変更を「同名衝突なしに新規作成 → 旧削除」の順で通せる。
resource "google_certificate_manager_dns_authorization" "internal" {
  name     = "${local.internal_lb_name}-v2"
  location = local.region
  domain   = local.internal_lb_hostname
  labels   = local.common_labels

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_certificate_manager_certificate" "internal" {
  name     = "${local.internal_lb_name}-v2"
  location = local.region
  labels   = local.common_labels

  managed {
    domains            = [local.internal_lb_hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.internal.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Gateway の dynamic IP は再作成で VIP が変わり DNS を壊すため NamedAddress で固定
resource "google_compute_address" "internal_lb" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  name         = local.internal_lb_name
  region       = local.region
  subnetwork   = google_compute_subnetwork.workload.id
  address_type = "INTERNAL"
}

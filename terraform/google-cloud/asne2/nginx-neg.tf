# GKE NEG controller が kubectl 側で apply された nginx Service annotation から生成する
# standalone zonal NEG 群を data で参照し、Global External ALB の backend service への供給元として
# outputs から公開する。

# NEG が生成された zone は Autopilot の capacity 判断次第で 2 zone にしか散らないケースがある。
# Service annotation cloud.google.com/neg-status を唯一の source of truth にして、
# 実際に NEG が存在する zone だけを for_each で回す。
# GKE cluster ができるまで annotation は取れないので depends_on で apply 段階まで遅らせる
data "external" "nginx_neg_zones" {
  program = ["${path.module}/../scripts/nginx_neg_zones.sh"]
  query = {
    project    = data.google_client_config.default.project
    membership = google_gke_hub_membership.bunshin.membership_id
    namespace  = "bunshin"
    service    = "nginx"
    neg_name   = local.nginx_neg_name
  }

  depends_on = [google_gke_hub_membership.bunshin]
}

data "google_compute_network_endpoint_group" "nginx" {
  for_each = toset(split(",", data.external.nginx_neg_zones.result.zones))
  name     = local.nginx_neg_name
  zone     = each.value
}

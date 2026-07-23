data "external" "nginx_neg_zones" {
  program = ["${path.module}/../scripts/nginx_neg_zones.sh"]
  query = {
    project    = data.google_client_config.default.project
    membership = google_gke_hub_membership.bunshin.membership_id
    namespace  = "bunshin"
    service    = "nginx"
    neg_name   = local.nginx_neg_name
  }
}

data "google_compute_network_endpoint_group" "nginx" {
  for_each = toset(split(",", data.external.nginx_neg_zones.result.zones))
  name     = local.nginx_neg_name
  zone     = each.value
}

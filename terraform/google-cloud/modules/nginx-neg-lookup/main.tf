data "external" "zones" {
  program = ["${path.module}/scripts/nginx_neg_zones.sh"]
  query = {
    project    = var.project
    membership = var.membership_id
    namespace  = var.namespace
    service    = var.service
    neg_name   = var.neg_name
  }
}

data "google_compute_network_endpoint_group" "nginx" {
  for_each = toset(compact(split(",", data.external.zones.result.zones)))
  name     = var.neg_name
  zone     = each.value
}

module "nginx_neg" {
  source = "../modules/nginx-neg-lookup"

  project       = data.google_client_config.default.project
  membership_id = local.gke_membership_id
  namespace     = "bunshin"
  service       = "nginx"
  neg_name      = local.nginx_neg_name
}

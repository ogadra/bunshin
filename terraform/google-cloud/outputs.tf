# Consumed by scripts/google-cloud/deploy.sh via `terraform output -raw` to
# render deploy/google-cloud manifests at kubectl apply time.
output "domain_name" {
  description = "FQDN served by nginx (INTERNAL_DOMAIN env var)"
  value       = var.domain_name
}

output "broker_gsa_email" {
  description = "Broker workload identity GSA email (annotated on the broker KSA)"
  value       = google_service_account.broker.email
}

output "nginx_resolver_asne1" {
  description = "asne1 kube-dns Service IP consumed as NGINX_RESOLVER by deploy/google-cloud/base/deploy-nginx.yaml"
  value       = module.asne1.nginx_resolver
}

output "nginx_resolver_asne2" {
  description = "asne2 kube-dns Service IP consumed as NGINX_RESOLVER by deploy/google-cloud/base/deploy-nginx.yaml"
  value       = module.asne2.nginx_resolver
}

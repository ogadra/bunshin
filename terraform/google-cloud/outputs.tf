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

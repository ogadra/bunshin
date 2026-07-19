# Consumed by the manifest rendering pipeline in scripts/google-cloud/deploy.sh
# to fill ${GOOGLE_CLOUD_PROJECT}, ${INTERNAL_DOMAIN}, and ${BROKER_GSA_EMAIL}
# at kubectl apply time. Image references are built inline from ${REGION} +
# ${GOOGLE_CLOUD_PROJECT} + a hardcoded artifact-registry repository ("bunshin").
output "project_id" {
  description = "GCP project ID hosting bunshin"
  value       = data.google_project.current.project_id
}

output "domain_name" {
  description = "FQDN served by nginx (INTERNAL_DOMAIN env var)"
  value       = var.domain_name
}

output "broker_gsa_email" {
  description = "Broker workload identity GSA email (annotated on the broker KSA)"
  value       = google_service_account.broker.email
}

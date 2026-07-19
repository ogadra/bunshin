output "system" {
  description = "Values wired into k8s manifests by deploy.sh; not intended for humans"
  value = {
    broker_gsa_email = google_service_account.broker.email
    domain_name      = var.domain_name
    nginx_resolver = {
      asne1 = module.asne1.nginx_resolver
      asne2 = module.asne2.nginx_resolver
    }
  }
}

output "user_dns" {
  description = "DNS records to publish for var.domain_name in the operator's DNS provider"
  value = {
    a_record    = google_compute_global_address.external_ipv4.address
    aaaa_record = google_compute_global_address.external_ipv6.address
  }
}

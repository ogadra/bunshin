output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.bunshin.self_link
}

output "nginx_neg_ids" {
  description = "IDs of nginx standalone zonal NEGs backing the Global External ALB"
  value       = [for _, neg in data.google_compute_network_endpoint_group.nginx : neg.id]
}

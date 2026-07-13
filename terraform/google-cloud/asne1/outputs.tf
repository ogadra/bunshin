output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.bunshin.self_link
}

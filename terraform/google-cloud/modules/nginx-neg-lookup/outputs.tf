output "ids" {
  description = "Self links of the discovered standalone zonal NEGs (empty when the Service or annotation is not reachable)"
  value       = [for _, neg in data.google_compute_network_endpoint_group.nginx : neg.id]
}

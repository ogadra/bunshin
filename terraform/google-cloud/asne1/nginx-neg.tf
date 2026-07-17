# GKE NEG controllerがnginx Service annotationから生成するstandalone zonal NEG群をdataで参照し、
# Global External ALBのbackend serviceへの供給元としてoutputsから公開する
data "google_compute_network_endpoint_group" "nginx" {
  for_each = toset(local.nginx_neg_zones)
  name     = local.nginx_neg_name
  zone     = each.value

  depends_on = [kubernetes_service_v1.nginx]
}

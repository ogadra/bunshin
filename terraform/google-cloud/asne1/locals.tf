locals {
  region = "asia-northeast1"

  workload_subnet_cidr    = "10.2.0.0/24"
  pods_secondary_cidr     = "10.2.16.0/20"
  services_secondary_cidr = "10.2.32.0/26"
  proxy_only_subnet_cidr  = "10.2.64.0/24"

  common_labels = {
    project    = "bunshin"
    managed_by = "terraform"
  }

  # Kubernetes Service DNS 上の broker host。ECS 側の CloudMap `broker.internal` と対応
  broker_host = "broker.bunshin.svc.cluster.local"

  # nginx / broker が listen する port と runner の container port。ECS locals の ecs_services と対称
  service_ports = {
    nginx  = 8080
    broker = 8080
    runner = 3000
  }

  image_registry = "${local.region}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.bunshin.repository_id}"

  internal_lb_name     = "bunshin-internal-${local.region}"
  internal_lb_hostname = "${local.region}.${var.domain_name}"
}

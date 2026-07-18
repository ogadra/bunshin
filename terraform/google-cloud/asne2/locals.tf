locals {
  region = "asia-northeast2"

  workload_subnet_cidr    = "10.3.0.0/24"
  pods_secondary_cidr     = "10.3.16.0/20"
  services_secondary_cidr = "10.3.32.0/26"
  proxy_only_subnet_cidr  = "10.3.64.0/24"

  common_labels = {
    project    = "bunshin"
    managed_by = "terraform"
  }

  # Kubernetes Service DNS 上の broker host。ECS 側の CloudMap `broker.internal` と対応
  broker_host = "broker.${kubernetes_namespace_v1.bunshin.metadata[0].name}.svc.cluster.local"

  # nginx / broker が listen する port と runner の container port。ECS locals の ecs_services と対称
  service_ports = {
    nginx  = 8080
    broker = 8080
    runner = 3000
  }

  image_registry = "${local.region}-docker.pkg.dev/${data.google_client_config.default.project}/${google_artifact_registry_repository.bunshin.repository_id}"

  internal_lb_name     = "bunshin-internal-${local.region}"
  internal_lb_hostname = "${local.region}.${var.domain_name}"

  # AutopilotがPodを3-zone spreadで配置する前提で、NEG lookup zoneを固定する。data.google_compute_zonesは
  # 未使用zoneまで返しNEG未生成zoneでplanが落ちるため使わない
  nginx_neg_name  = "bunshin-nginx-${local.region}"
  nginx_neg_zones = ["${local.region}-a", "${local.region}-b", "${local.region}-c"]

  broker_service_account_email = basename(var.broker_service_account_id)
}

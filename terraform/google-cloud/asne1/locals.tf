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

  # nginx / broker が listen する port と runner の container port。ECS locals の ecs_services と対称
  service_ports = {
    nginx  = 8080
    broker = 8080
    runner = 3000
  }

  # port-forwardで外部から届けたいrunner内アプリのlisten port。
  # 既定のrunner API (:3000) とは別のNetworkPolicyとService portで参照する。
  runner_app_port = 5000

  internal_lb_name     = "bunshin-internal-${local.region}"
  internal_lb_hostname = "${local.region}.${var.domain_name}"

  # Autopilot が Pod を 3-zone spread で配置する前提で、NEG lookup zone を固定する
  # data.google_compute_zones は未使用 zone まで返し NEG 未生成 zone で plan が落ちるため使わない
  nginx_neg_name  = "bunshin-nginx-${local.region}"
  nginx_neg_zones = ["${local.region}-a", "${local.region}-b", "${local.region}-c"]
}

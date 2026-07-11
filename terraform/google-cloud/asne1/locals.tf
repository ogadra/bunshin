locals {
  region = "asia-northeast1"

  workload_subnet_cidr    = "10.2.0.0/24"
  pods_secondary_cidr     = "10.2.16.0/20"
  services_secondary_cidr = "10.2.32.0/26"
  proxy_only_subnet_cidr  = "10.2.64.0/24"
}

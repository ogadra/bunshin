locals {
  region = "asia-northeast2"

  workload_subnet_cidr    = "10.3.0.0/24"
  pods_secondary_cidr     = "10.3.16.0/20"
  services_secondary_cidr = "10.3.32.0/26"
  proxy_only_subnet_cidr  = "10.3.64.0/24"
}

variable "deployer_email" {
  description = "Google identity email that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string
}

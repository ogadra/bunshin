variable "deployer_email" {
  description = "Google identity email that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string
}

variable "broker_service_account_email" {
  description = "Broker GSA email; annotated on the broker KSA for Workload Identity"
  type        = string
}

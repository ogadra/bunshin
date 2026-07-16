variable "deployer_email" {
  description = "Google identity email that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string
}

variable "broker_service_account_email" {
  description = "Broker GSA email; annotated on the broker KSA for Workload Identity"
  type        = string
}

variable "broker_service_account_id" {
  description = "Broker GSA fully-qualified name (projects/-/serviceAccounts/...); bound to the region-scoped KSA identifier"
  type        = string
}

variable "bunshin_stacks" {
  description = "Stack identifiers advertised to nginx / broker"
  type        = list(string)
}

variable "domain_name" {
  description = "Apex domain used by nginx to compose internal / external hosts"
  type        = string
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry"
  type        = string
}

variable "nginx_desired_count" {
  description = "Desired number of nginx Pod replicas"
  type        = number
}

variable "broker_desired_count" {
  description = "Desired number of broker Pod replicas"
  type        = number
}

variable "runner_desired_count" {
  description = "Desired number of runner Pod replicas"
  type        = number
}

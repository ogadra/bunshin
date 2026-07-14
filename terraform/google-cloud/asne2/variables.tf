variable "broker_service_account_email" {
  description = "Broker GSA email; annotated on the broker KSA for Workload Identity"
  type        = string
}

variable "bunshin_stacks" {
  description = "Stack identifiers advertised to nginx / broker"
  type        = list(string)
}

variable "deployer_iam_member" {
  description = "IAM member string for the identity that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string
}

variable "domain_name" {
  description = "Apex domain used by nginx to compose internal / external hosts"
  type        = string
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry"
  type        = string
}

variable "project_id" {
  description = "Google Cloud project ID for env value injection (avoids per-region data lookup)"
  type        = string
}

variable "runner_desired_count" {
  description = "Desired number of runner Pod replicas"
  type        = number
}

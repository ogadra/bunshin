variable "domain_name" {
  description = "FQDN for the service"
  type        = string
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry (typically the git SHA)"
  type        = string

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must be non-empty."
  }
}

variable "runner_desired_count" {
  description = "Desired number of runner Pod replicas"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0 && floor(var.runner_desired_count) == var.runner_desired_count
    error_message = "runner_desired_count must be a non-negative integer."
  }
}

# subject にする identity は Kubernetes API 内の RBAC 側で解決される。iam.gserviceaccount.com の GSA も
# ユーザーも同じ書式 (`user:foo@example.com` / `serviceAccount:foo@<project>.iam.gserviceaccount.com`) で通す
variable "deployer_iam_member" {
  description = "IAM member string for the identity that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string

  validation {
    condition     = can(regex("^(user|serviceAccount|group):.+$", var.deployer_iam_member))
    error_message = "deployer_iam_member must be prefixed with user:, serviceAccount:, or group:."
  }
}

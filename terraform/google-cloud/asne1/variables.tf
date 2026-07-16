variable "deployer_iam_member" {
  description = "IAM member string for the identity that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string

  validation {
    condition     = can(regex("^(user|serviceAccount|group):.+$", var.deployer_iam_member))
    error_message = "deployer_iam_member must be prefixed with user:, serviceAccount:, or group:."
  }
}

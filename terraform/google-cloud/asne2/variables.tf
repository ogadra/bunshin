variable "deployer_iam_member" {
  description = "IAM member string for the identity that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string
}

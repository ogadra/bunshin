variable "deploy_principal" {
  description = "GKE Hub Connect Gateway へのアクセスを付与する IAM member (user:/group:/serviceAccount: プレフィックス付き)"
  type        = string

  validation {
    condition     = can(regex("^(user|group|serviceAccount):", var.deploy_principal))
    error_message = "deploy_principal must start with 'user:', 'group:', or 'serviceAccount:'."
  }
}

variable "deploy_principal" {
  description = "GKE Hub Connect Gateway へのアクセスを付与する IAM member (user:/group:/serviceAccount: プレフィックス付き)"
  type        = string
}

# Deploy role ARNs for GitHub Actions OIDC authentication
output "deploy_role_arns" {
  description = "Map of service name to deploy IAM role ARN"
  value       = { for k, v in aws_iam_role.github_actions_deploy : k => v.arn }
}

output "external_alb_dns_names" {
  description = "Map of region short name to external ALB DNS name"
  value = {
    apne1 = module.apne1.external_alb_dns_name
    apne3 = module.apne3.external_alb_dns_name
  }
}

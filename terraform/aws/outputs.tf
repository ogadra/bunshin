# Deploy role ARNs for GitHub Actions OIDC authentication
output "deploy_role_arns" {
  description = "Map of service name to deploy IAM role ARN"
  value       = { for k, v in aws_iam_role.github_actions_deploy : k => v.arn }
}

# Consumed by ecspresso via tfstate plugin for nginx INTERNAL_DOMAIN env var
output "domain_name" {
  description = "FQDN served by nginx, consumed at deploy render time"
  value       = var.domain_name
}

output "user_dns" {
  description = "DNS records to publish for var.domain_name in the external authoritative zone (NS1 + Route53 multi provider)"
  value = {
    aliases = {
      port_forward_apne1 = {
        target  = aws_cloudfront_distribution.port_forward_apne1.domain_name
        zone_id = aws_cloudfront_distribution.port_forward_apne1.hosted_zone_id
      }
      port_forward_apne3 = {
        target  = aws_cloudfront_distribution.port_forward_apne3.domain_name
        zone_id = aws_cloudfront_distribution.port_forward_apne3.hosted_zone_id
      }
    }
  }
}

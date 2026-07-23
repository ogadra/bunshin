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
      main = {
        name    = var.domain_name
        target  = aws_cloudfront_distribution.main.domain_name
        zone_id = aws_cloudfront_distribution.main.hosted_zone_id
      }
      api_ingress_origin = {
        name    = local.api_ingress_origin_domain_name
        target  = aws_globalaccelerator_accelerator.api_ingress.dns_name
        zone_id = aws_globalaccelerator_accelerator.api_ingress.hosted_zone_id
      }
      port_forward_apne1 = {
        name    = "*.ap-northeast-1.${var.domain_name}"
        target  = aws_cloudfront_distribution.port_forward_apne1.domain_name
        zone_id = aws_cloudfront_distribution.port_forward_apne1.hosted_zone_id
      }
      port_forward_apne3 = {
        name    = "*.ap-northeast-3.${var.domain_name}"
        target  = aws_cloudfront_distribution.port_forward_apne3.domain_name
        zone_id = aws_cloudfront_distribution.port_forward_apne3.hosted_zone_id
      }
    }
  }
}

output "apne1_nginx_security_group_id" {
  description = "Consumed by terraform/shared to attach cross-cloud HTTPS SG rules"
  value       = module.apne1.nginx_security_group_id
}

output "apne1_internal_alb_security_group_id" {
  description = "Consumed by terraform/shared to attach cross-cloud HTTPS SG rules"
  value       = module.apne1.internal_alb_security_group_id
}

output "apne3_nginx_security_group_id" {
  description = "Consumed by terraform/shared to attach cross-cloud HTTPS SG rules"
  value       = module.apne3.nginx_security_group_id
}

output "apne3_internal_alb_security_group_id" {
  description = "Consumed by terraform/shared to attach cross-cloud HTTPS SG rules"
  value       = module.apne3.internal_alb_security_group_id
}

output "user_dns_acm_validation" {
  description = "ACM DNS validation CNAMEs to publish in the external authoritative zone before re-applying"
  value = {
    port_forward_apne1 = {
      name = one(aws_acm_certificate.cloudfront_port_forward_apne1.domain_validation_options).resource_record_name
      data = one(aws_acm_certificate.cloudfront_port_forward_apne1.domain_validation_options).resource_record_value
    }
    port_forward_apne3 = {
      name = one(aws_acm_certificate.cloudfront_port_forward_apne3.domain_validation_options).resource_record_name
      data = one(aws_acm_certificate.cloudfront_port_forward_apne3.domain_validation_options).resource_record_value
    }
  }
}

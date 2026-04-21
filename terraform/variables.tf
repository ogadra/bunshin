variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the ALB HTTPS listener"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "FQDN for the service (e.g. ogadra-bunshin.mad.bcr.dev)"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile name for the target account"
  type        = string
}

variable "proxy_secret" {
  description = "Secret header value for Cloudflare Workers proxy verification via WAF"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.proxy_secret) >= 50
    error_message = "proxy_secret must be at least 50 characters."
  }
}

variable "runner_desired_count" {
  description = "Desired number of runner ECS tasks"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0
    error_message = "runner_desired_count must be non-negative."
  }
}

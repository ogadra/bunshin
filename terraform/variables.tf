variable "domain_name" {
  description = "Domain name for ALB ACM certificate lookup"
  type        = string
  sensitive   = true
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
    condition     = length(var.proxy_secret) >= 16 && length(var.proxy_secret) <= 50
    error_message = "proxy_secret must be between 16 and 50 characters."
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

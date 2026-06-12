variable "external_alb_certificate_arn" {
  description = "ACM certificate ARN for the external ALB HTTPS listener"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:acm:ap-northeast-1:[0-9]{12}:certificate/.+", var.external_alb_certificate_arn))
    error_message = "external_alb_certificate_arn must be an ap-northeast-1 ACM certificate ARN."
  }
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
    condition     = var.runner_desired_count >= 0 && floor(var.runner_desired_count) == var.runner_desired_count
    error_message = "runner_desired_count must be a non-negative integer."
  }
}

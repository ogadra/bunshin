variable "alb_certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listeners"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:acm:ap-northeast-3:[0-9]{12}:certificate/.+", var.alb_certificate_arn))
    error_message = "alb_certificate_arn must be an ap-northeast-3 ACM certificate ARN."
  }
}

variable "domain_name" {
  description = "FQDN for the service"
  type        = string
}

variable "runner_desired_count" {
  description = "Desired number of runner ECS tasks"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0 && floor(var.runner_desired_count) == var.runner_desired_count
    error_message = "runner_desired_count must be a non-negative integer."
  }
}

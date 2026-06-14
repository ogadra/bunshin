variable "alb_certificate_arns" {
  description = "ACM certificate ARNs for ALB HTTPS listeners"
  type = object({
    apne1 = string
    apne3 = string
  })
  sensitive = true

  validation {
    condition = (
      can(regex("^arn:aws:acm:ap-northeast-1:[0-9]{12}:certificate/.+", var.alb_certificate_arns.apne1)) &&
      can(regex("^arn:aws:acm:ap-northeast-3:[0-9]{12}:certificate/.+", var.alb_certificate_arns.apne3))
    )
    error_message = "alb_certificate_arns must contain ACM certificate ARNs in their matching regions."
  }
}

variable "domain_name" {
  description = "FQDN for the service"
  type        = string
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for the CloudFront distribution"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/.+", var.cloudfront_certificate_arn))
    error_message = "cloudfront_certificate_arn must be a us-east-1 ACM certificate ARN."
  }
}

variable "aws_profile" {
  description = "AWS CLI profile name for the target account"
  type        = string
}

variable "runner_desired_count" {
  description = "Desired number of runner ECS tasks"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0
    error_message = "runner_desired_count must be non-negative."
  }
}

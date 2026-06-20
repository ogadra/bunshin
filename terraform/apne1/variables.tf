variable "alb_certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listeners"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:acm:ap-northeast-1:[0-9]{12}:certificate/.+", var.alb_certificate_arn))
    error_message = "alb_certificate_arn must be an ap-northeast-1 ACM certificate ARN."
  }
}

variable "domain_name" {
  description = "FQDN for the service"
  type        = string
}

variable "bunshin_stacks" {
  description = "Bunshin stack regions shared by every broker"
  type        = list(string)

  validation {
    condition = (
      length(var.bunshin_stacks) > 0 &&
      length(distinct(var.bunshin_stacks)) == length(var.bunshin_stacks) &&
      alltrue([
        for stack in var.bunshin_stacks :
        can(regex("^[a-z0-9-]+$", stack))
      ])
    )
    error_message = "bunshin_stacks must be a non-empty list of unique stack identifiers matching [a-z0-9-]+."
  }
}

variable "peer_vpc" {
  description = "Peer VPC for cross-region routing and internal DNS resolution"
  type = object({
    id                    = string
    region                = string
    cidr                  = string
    peering_connection_id = string
  })
}

variable "runner_desired_count" {
  description = "Desired number of runner ECS tasks"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0 && floor(var.runner_desired_count) == var.runner_desired_count
    error_message = "runner_desired_count must be a non-negative integer."
  }
}

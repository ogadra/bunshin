variable "domain_name" {
  description = "FQDN for the service"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS-1123 hostname with at least one dot."
  }
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry (typically the git SHA)"
  type        = string

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must be non-empty."
  }
}

variable "nginx_desired_count" {
  description = "Desired number of nginx Pod replicas per region"
  type        = number

  validation {
    condition     = var.nginx_desired_count >= 0 && floor(var.nginx_desired_count) == var.nginx_desired_count
    error_message = "nginx_desired_count must be a non-negative integer."
  }
}

variable "broker_desired_count" {
  description = "Desired number of broker Pod replicas per region"
  type        = number

  validation {
    condition     = var.broker_desired_count >= 0 && floor(var.broker_desired_count) == var.broker_desired_count
    error_message = "broker_desired_count must be a non-negative integer."
  }
}

variable "runner_desired_count" {
  description = "Desired number of runner Pod replicas per region"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0 && floor(var.runner_desired_count) == var.runner_desired_count
    error_message = "runner_desired_count must be a non-negative integer."
  }
}

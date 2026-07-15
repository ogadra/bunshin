variable "domain_name" {
  description = "FQDN for the service"
  type        = string
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry (typically the git SHA)"
  type        = string

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must be non-empty."
  }
}

variable "runner_desired_count" {
  description = "Desired number of runner Pod replicas"
  type        = number

  validation {
    condition     = var.runner_desired_count >= 0 && floor(var.runner_desired_count) == var.runner_desired_count
    error_message = "runner_desired_count must be a non-negative integer."
  }
}

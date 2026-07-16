variable "deployer_email" {
  description = "Google identity email that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.deployer_email))
    error_message = "deployer_email must be a valid email address."
  }
}

variable "broker_service_account_email" {
  description = "Broker GSA email; annotated on the broker KSA for Workload Identity"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.broker_service_account_email))
    error_message = "broker_service_account_email must be a GSA email (\"<name>@<project>.iam.gserviceaccount.com\")."
  }
}

variable "broker_service_account_id" {
  description = "Broker GSA fully-qualified name (projects/-/serviceAccounts/...); bound to the region-scoped KSA identifier"
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/serviceAccounts/[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.broker_service_account_id))
    error_message = "broker_service_account_id must be projects/<project>/serviceAccounts/<name>@<project>.iam.gserviceaccount.com."
  }
}

variable "bunshin_stacks" {
  description = "Stack identifiers advertised to nginx / broker"
  type        = list(string)

  validation {
    condition     = length(var.bunshin_stacks) > 0
    error_message = "bunshin_stacks must be non-empty."
  }
}

variable "domain_name" {
  description = "Apex domain used by nginx to compose internal / external hosts"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS-1123 hostname with at least one dot."
  }
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry"
  type        = string

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must be non-empty."
  }
}

variable "nginx_desired_count" {
  description = "Desired number of nginx Pod replicas"
  type        = number

  validation {
    condition     = var.nginx_desired_count >= 0 && floor(var.nginx_desired_count) == var.nginx_desired_count
    error_message = "nginx_desired_count must be a non-negative integer."
  }
}

variable "broker_desired_count" {
  description = "Desired number of broker Pod replicas"
  type        = number

  validation {
    condition     = var.broker_desired_count >= 0 && floor(var.broker_desired_count) == var.broker_desired_count
    error_message = "broker_desired_count must be a non-negative integer."
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

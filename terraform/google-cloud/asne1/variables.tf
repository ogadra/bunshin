variable "deployer_email" {
  description = "Google identity email that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string
}

variable "broker_service_account_email" {
  description = "Broker GSA email; annotated on the broker KSA for Workload Identity"
  type        = string
}

variable "broker_service_account_id" {
  description = "Broker GSA fully-qualified name (projects/-/serviceAccounts/...); bound to the region-scoped KSA identifier"
  type        = string
}

variable "bunshin_stacks" {
  description = "Stack identifiers advertised to nginx / broker"
  type        = list(string)
}

variable "desired_counts" {
  description = "Pod replica counts keyed by microservice (nginx / broker / runner)"
  type        = map(number)

  validation {
    condition     = length(setsubtract(["nginx", "broker", "runner"], keys(var.desired_counts))) == 0
    error_message = "desired_counts must contain nginx, broker, and runner keys."
  }

  validation {
    condition     = alltrue([for v in values(var.desired_counts) : v >= 0 && floor(v) == v])
    error_message = "desired_counts values must be non-negative integers."
  }
}

variable "domain_name" {
  description = "Apex domain used by nginx to compose internal / external hosts"
  type        = string
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry"
  type        = string
}

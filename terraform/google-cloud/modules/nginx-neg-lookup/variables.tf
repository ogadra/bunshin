variable "project" {
  description = "GCP project ID that owns the GKE cluster / fleet membership and the standalone zonal NEGs"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project))
    error_message = "project must be a valid GCP project ID (6-30 lowercase alphanumerics / hyphens)."
  }
}

variable "membership_id" {
  description = "GKE Hub fleet membership_id used to reach the cluster via Connect Gateway"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}[a-z0-9]$", var.membership_id))
    error_message = "membership_id must be a valid fleet membership ID (lowercase alphanumerics / hyphens)."
  }
}

variable "namespace" {
  description = "Kubernetes namespace hosting the nginx Service that owns the standalone NEG"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a DNS-1123 label."
  }
}

variable "service" {
  description = "Kubernetes Service name whose cloud.google.com/neg-status annotation lists the created NEG zones"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.service)) && length(var.service) <= 63
    error_message = "service must be a DNS-1123 label."
  }
}

variable "neg_name" {
  description = "Standalone zonal NEG name declared in the nginx Service cloud.google.com/neg annotation"
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.neg_name))
    error_message = "neg_name must be a valid GCP resource name (RFC 1035 label)."
  }
}

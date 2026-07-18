variable "deployer_email" {
  description = "Google identity email that runs terraform apply (bound to cluster-admin via RBAC)"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.deployer_email))
    error_message = "deployer_email must be a valid email address."
  }
}

variable "broker_service_account_id" {
  description = "Broker GSA fully-qualified name (projects/-/serviceAccounts/<email>); email is derived via basename() and annotated on the KSA for Workload Identity"
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/serviceAccounts/[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.broker_service_account_id))
    error_message = "broker_service_account_id must be projects/<project>/serviceAccounts/<gsa-email>."
  }
}

variable "bunshin_stacks" {
  description = "Stack identifiers advertised to nginx / broker; each element is a GCP region name (e.g. asia-northeast1)"
  type        = list(string)

  validation {
    condition     = length(var.bunshin_stacks) > 0 && alltrue([for s in var.bunshin_stacks : can(regex("^[a-z]+-[a-z]+[0-9]+$", s))])
    error_message = "bunshin_stacks must be a non-empty list of GCP region names matching ^[a-z]+-[a-z]+[0-9]+$."
  }
}

variable "desired_counts" {
  description = "Pod replica counts keyed by microservice"
  type = object({
    nginx  = number
    broker = number
    runner = number
  })

  validation {
    condition     = alltrue([for v in values(var.desired_counts) : v >= 0 && floor(v) == v])
    error_message = "desired_counts values must be non-negative integers."
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
  description = "Container image tag pulled from Artifact Registry (git commit SHA, 40 hex chars; immutable, matches broker/nginx/runner checkov CKV_K8S_15/43 skips)"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be a 40-character lowercase git commit SHA (^[0-9a-f]{40}$)."
  }
}

variable "peer_vpc_network" {
  description = "Peer region VPC self_link for cross-region private DNS visibility (asne2 zone must resolve from asne1 VPC and vice versa)"
  type        = string

  validation {
    condition     = can(regex("^https://www\\.googleapis\\.com/compute/v1/projects/[^/]+/global/networks/[^/]+$", var.peer_vpc_network))
    error_message = "peer_vpc_network must be a compute network self_link (https://www.googleapis.com/compute/v1/projects/<project>/global/networks/<name>)."
  }
}

variable "project_id" {
  description = "GCP project ID resolved at root from data.google_project.current (GOOGLE_CLOUD_PROJECT env); passed in because the google_project data source does not honor the alias provider's project attribute"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must match GCP project ID format (6-30 chars, lowercase / digits / hyphen, starts with a letter, does not end with a hyphen)."
  }
}

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
}

variable "image_tag" {
  description = "Container image tag pulled from Artifact Registry"
  type        = string
}

variable "peer_vpc_network" {
  description = "Peer region VPC self_link for cross-region private DNS visibility (asne2 zone must resolve from asne1 VPC and vice versa)"
  type        = string
}

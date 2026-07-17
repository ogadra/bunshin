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

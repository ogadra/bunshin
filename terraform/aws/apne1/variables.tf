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

variable "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN allowed to read static assets"
  type        = string
}

variable "static_replication_destination_bucket_arn" {
  description = "ARN of the secondary static asset bucket"
  type        = string
}

variable "static_replication_destination_bucket_versioning_status" {
  description = "Versioning status of the secondary static asset bucket"
  type        = string
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

locals {
  ecs_services = {
    nginx  = { port = 8080 }
    broker = { port = 8080 }
    runner = { port = 3000 }
  }

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }

  api_ingress_origin_domain_name = "api-ingress.${var.domain_name}"

  # GCP asne1/asne2 workload subnet CIDR。Cloud DNS inbound forwarder はこの subnet から IP を払い出すため、
  # OUTBOUND resolver endpoint の SG egress destination として使う。GCP 側 locals と同期する
  gcp_forwarder_subnet_cidrs = ["10.2.0.0/24", "10.3.0.0/24"]
}

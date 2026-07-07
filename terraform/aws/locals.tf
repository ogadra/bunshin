locals {
  ecs_services = {
    nginx  = { port = 8080 }
    broker = { port = 8080 }
    runner = { port = 3000 }
  }

  bunshin_stacks = [
    data.aws_region.apne1.region,
    data.aws_region.apne3.region,
  ]

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }

  api_ingress_origin_domain_name = "api-ingress.${var.domain_name}"
}

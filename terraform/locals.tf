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

  api_ingress_origins = {
    apne1 = {
      domain_name = "api-ingress-apne1.${var.domain_name}"
      dns_name    = module.apne1.api_ingress_alb_dns_name
      zone_id     = module.apne1.api_ingress_alb_zone_id
    }
    apne3 = {
      domain_name = "api-ingress-apne3.${var.domain_name}"
      dns_name    = module.apne3.api_ingress_alb_dns_name
      zone_id     = module.apne3.api_ingress_alb_zone_id
    }
  }

  external_albs = {
    apne1 = {
      region   = "ap-northeast-1"
      dns_name = module.apne1.external_alb_dns_name
      zone_id  = module.apne1.external_alb_zone_id
    }
    apne3 = {
      region   = "ap-northeast-3"
      dns_name = module.apne3.external_alb_dns_name
      zone_id  = module.apne3.external_alb_zone_id
    }
  }
}

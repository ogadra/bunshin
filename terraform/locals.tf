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

  static_bucket_name = "bunshin-${data.aws_caller_identity.current.account_id}-${substr(sha256(var.domain_name), 0, 12)}-static"

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

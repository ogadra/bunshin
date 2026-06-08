locals {
  ecs_services = {
    nginx  = { port = 8080 }
    broker = { port = 8080 }
    runner = { port = 3000 }
  }

  root_ecs_services = {
    nginx  = local.ecs_services["nginx"]
    runner = local.ecs_services["runner"]
  }

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }

  # Destination regions for JP cross-region inference profile from ap-northeast-1
  jp_cris_destination_regions = [
    "ap-northeast-1",
    "ap-northeast-3",
  ]
}

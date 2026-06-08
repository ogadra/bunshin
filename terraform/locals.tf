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

  apne1_ecs_subnet_ids = slice(module.apne1.private_subnet_ids, 0, 2)

  # Destination regions for JP cross-region inference profile from ap-northeast-1
  jp_cris_destination_regions = [
    "ap-northeast-1",
    "ap-northeast-3",
  ]
}

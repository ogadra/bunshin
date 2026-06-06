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

  # Destination regions for JP cross-region inference profile from ap-northeast-1
  jp_cris_destination_regions = [
    "ap-northeast-1",
    "ap-northeast-3",
  ]
}

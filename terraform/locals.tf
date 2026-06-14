locals {
  ecs_services = {
    nginx  = { port = 8080 }
    broker = { port = 8080 }
    runner = { port = 3000 }
  }

  bunshin_stacks = [
    data.aws_region.apne1.id,
    data.aws_region.apne3.id,
  ]

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }
}

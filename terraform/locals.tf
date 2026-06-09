locals {
  ecs_services = {
    nginx  = { port = 8080 }
    broker = { port = 8080 }
    runner = { port = 3000 }
  }

  root_ecs_services = {
    nginx = local.ecs_services["nginx"]
  }

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }

}

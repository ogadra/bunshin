locals {
  azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]

  public_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  apne3_vpc_cidr      = "10.1.0.0/16"
  azs_apne3           = ["ap-northeast-3a", "ap-northeast-3b", "ap-northeast-3c"]
  public_cidrs_apne3  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_cidrs_apne3 = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

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

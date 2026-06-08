locals {
  vpc_cidr      = "10.1.0.0/16"
  azs           = ["ap-northeast-3a", "ap-northeast-3b", "ap-northeast-3c"]
  public_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_cidrs = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

  ecs_services = {
    broker = { port = 8080 }
  }

  broker_desired_count = 6
  broker_subnet_ids    = slice(aws_subnet.apne3_private[*].id, 0, 2)

  ecr_registry          = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com"
  broker_repository_arn = "arn:aws:ecr:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:repository/bunshin/broker"

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }
}

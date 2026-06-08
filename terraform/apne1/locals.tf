locals {
  vpc_cidr      = "10.0.0.0/16"
  azs           = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  public_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  broker_port          = 8080
  broker_desired_count = 6
  ecs_subnet_ids       = slice(aws_subnet.apne1_private[*].id, 0, 2)

  ecr_registry          = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com"
  broker_repository_arn = "arn:aws:ecr:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:repository/bunshin/broker"

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }
}

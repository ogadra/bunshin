module "apne1" {
  source = "./apne1"

  alb_certificate_arn  = var.alb_certificate_arns.apne1
  bunshin_stacks       = local.bunshin_stacks
  domain_name          = var.domain_name
  runner_desired_count = var.runner_desired_count

  peer_vpc = {
    id                    = module.apne3.vpc_id
    region                = "ap-northeast-3"
    cidr                  = module.apne3.vpc_cidr
    peering_connection_id = aws_vpc_peering_connection_accepter.apne1_apne3.id
  }

  providers = {
    aws = aws.apne1
  }
}

module "apne3" {
  source = "./apne3"

  alb_certificate_arn  = var.alb_certificate_arns.apne3
  bunshin_stacks       = local.bunshin_stacks
  domain_name          = var.domain_name
  runner_desired_count = var.runner_desired_count

  peer_vpc = {
    id                    = module.apne1.vpc_id
    region                = "ap-northeast-1"
    cidr                  = module.apne1.vpc_cidr
    peering_connection_id = aws_vpc_peering_connection_accepter.apne1_apne3.id
  }

  providers = {
    aws = aws.apne3
  }
}

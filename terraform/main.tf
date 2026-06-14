module "apne1" {
  source = "./apne1"

  alb_certificate_arn  = var.alb_certificate_arns.apne1
  bunshin_stacks       = local.bunshin_stacks
  domain_name          = var.domain_name
  runner_desired_count = var.runner_desired_count

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

  providers = {
    aws = aws.apne3
  }
}

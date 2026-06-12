module "apne1" {
  source = "./apne1"

  external_alb_certificate_arn = var.external_alb_certificate_arns.apne1
  proxy_secret                 = var.proxy_secret
  runner_desired_count         = var.runner_desired_count

  providers = {
    aws = aws.apne1
  }
}

module "apne3" {
  source = "./apne3"

  external_alb_certificate_arn = var.external_alb_certificate_arns.apne3
  proxy_secret                 = var.proxy_secret
  runner_desired_count         = var.runner_desired_count

  providers = {
    aws = aws.apne3
  }
}

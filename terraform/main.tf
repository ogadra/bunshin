module "apne1" {
  source = "./apne1"

  alb_certificate_arn                                     = var.alb_certificate_arns.apne1
  bunshin_stacks                                          = local.bunshin_stacks
  cloudfront_distribution_arn                             = aws_cloudfront_distribution.main.arn
  domain_name                                             = var.domain_name
  runner_desired_count                                    = var.runner_desired_count
  static_replication_destination_bucket_arn               = module.apne3.static_bucket_arn
  static_replication_destination_bucket_versioning_status = module.apne3.static_bucket_versioning_status

  providers = {
    aws = aws.apne1
  }
}

module "apne3" {
  source = "./apne3"

  alb_certificate_arn         = var.alb_certificate_arns.apne3
  bunshin_stacks              = local.bunshin_stacks
  cloudfront_distribution_arn = aws_cloudfront_distribution.main.arn
  domain_name                 = var.domain_name
  runner_desired_count        = var.runner_desired_count

  providers = {
    aws = aws.apne3
  }
}

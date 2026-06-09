module "apne1" {
  source = "./apne1"

  runner_desired_count = var.runner_desired_count

  providers = {
    aws = aws.apne1
  }
}

module "apne3" {
  source = "./apne3"

  runner_desired_count = var.runner_desired_count

  providers = {
    aws = aws.apne3
  }
}

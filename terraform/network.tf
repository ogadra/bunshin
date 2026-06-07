module "apne1" {
  source = "./apne1"

  providers = {
    aws = aws.apne1
  }
}

module "apne3" {
  source = "./apne3"

  providers = {
    aws = aws.apne3
  }
}

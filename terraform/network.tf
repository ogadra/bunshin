module "apne1" {
  source = "./apne1"

  providers = {
    aws = aws.apne1
  }

  vpc_cidr             = local.apne1_vpc_cidr
  azs                  = local.azs_apne1
  public_subnet_cidrs  = local.public_cidrs_apne1
  private_subnet_cidrs = local.private_cidrs_apne1
  tags                 = local.common_tags
}

module "apne3" {
  source = "./apne3"

  providers = {
    aws = aws.apne3
  }

  vpc_cidr             = local.apne3_vpc_cidr
  azs                  = local.azs_apne3
  public_subnet_cidrs  = local.public_cidrs_apne3
  private_subnet_cidrs = local.private_cidrs_apne3
  tags                 = local.common_tags
}

module "apne1" {
  source = "./apne1"

  peer_vpc_cidr             = module.apne3.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.apne1_apne3.id

  providers = {
    aws = aws.apne1
  }
}

module "apne3" {
  source = "./apne3"

  peer_vpc_cidr             = module.apne1.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.apne1_apne3.id

  providers = {
    aws = aws.apne3
  }
}

module "apne1" {
  source = "./apne1"

  alb_certificate_arn                                     = data.aws_acm_certificate.apne1_alb.arn
  cloudfront_distribution_arn                             = aws_cloudfront_distribution.main.arn
  domain_name                                             = var.domain_name
  google_cloud_dns_forwarder_source_range                 = local.google_cloud_dns_forwarder_source_range
  google_cloud_forwarder_subnet_cidrs                     = local.google_cloud_forwarder_subnet_cidrs
  static_replication_destination_bucket_arn               = module.apne3.static_bucket_arn
  static_replication_destination_bucket_versioning_status = module.apne3.static_bucket_versioning_status

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

  alb_certificate_arn                     = data.aws_acm_certificate.apne3_alb.arn
  cloudfront_distribution_arn             = aws_cloudfront_distribution.main.arn
  domain_name                             = var.domain_name
  google_cloud_dns_forwarder_source_range = local.google_cloud_dns_forwarder_source_range
  google_cloud_forwarder_subnet_cidrs     = local.google_cloud_forwarder_subnet_cidrs

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

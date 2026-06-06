# trivy:ignore:AVD-AWS-0178 -- VPC Flow Logs are out of scope for initial deployment
resource "aws_vpc" "apne3" {
  # checkov:skip=CKV2_AWS_11:VPC Flow Logs are out of scope for initial deployment
  provider = aws.apne3

  cidr_block           = local.apne3_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3"
  })
}

# Public subnets
resource "aws_subnet" "apne3_public" {
  provider = aws.apne3
  count    = length(local.azs_apne3)

  vpc_id            = aws_vpc.apne3.id
  cidr_block        = local.public_cidrs_apne3[count.index]
  availability_zone = local.azs_apne3[count.index]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-public-${local.azs_apne3[count.index]}"
  })
}

# Private subnets
resource "aws_subnet" "apne3_private" {
  provider = aws.apne3
  count    = length(local.azs_apne3)

  vpc_id            = aws_vpc.apne3.id
  cidr_block        = local.private_cidrs_apne3[count.index]
  availability_zone = local.azs_apne3[count.index]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-private-${local.azs_apne3[count.index]}"
  })
}

# Restrict the default security group to deny all traffic
resource "aws_default_security_group" "apne3" {
  provider = aws.apne3
  vpc_id   = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-default"
  })
}

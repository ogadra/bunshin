resource "aws_vpc" "apne3" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3"
  })
}

resource "aws_subnet" "apne3_public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.apne3.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-public-${local.azs[count.index]}"
  })
}

resource "aws_subnet" "apne3_private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.apne3.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-private-${local.azs[count.index]}"
  })
}

resource "aws_route_table" "apne3_private" {
  vpc_id = aws_vpc.apne3.id

  route {
    cidr_block                = var.peer_vpc_cidr
    vpc_peering_connection_id = var.vpc_peering_connection_id
  }

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-private"
  })
}

resource "aws_route_table_association" "apne3_private" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  count = length(local.azs)

  subnet_id      = aws_subnet.apne3_private[count.index].id
  route_table_id = aws_route_table.apne3_private.id
}

resource "aws_default_security_group" "apne3" {
  vpc_id = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-default"
  })
}

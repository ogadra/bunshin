resource "aws_vpc_peering_connection" "apne1_apne3" {
  provider = aws.apne1

  vpc_id      = module.apne1.vpc_id
  peer_vpc_id = module.apne3.vpc_id
  peer_region = "ap-northeast-3"
  auto_accept = false

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-apne3"
  })
}

resource "aws_vpc_peering_connection_accepter" "apne1_apne3" {
  provider = aws.apne3

  vpc_peering_connection_id = aws_vpc_peering_connection.apne1_apne3.id
  auto_accept               = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-apne3"
  })
}

resource "aws_vpc_peering_connection_options" "apne1_apne3_requester" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1

  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.apne1_apne3.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_vpc_peering_connection_options" "apne1_apne3_accepter" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne3

  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.apne1_apne3.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

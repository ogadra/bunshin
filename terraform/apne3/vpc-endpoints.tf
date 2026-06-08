resource "aws_vpc_endpoint" "apne3_dynamodb" {
  vpc_id       = aws_vpc.apne3.id
  service_name = "com.amazonaws.ap-northeast-3.dynamodb"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.apne3_private.id]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-dynamodb"
  })
}

resource "aws_security_group" "vpc_endpoint_for_ecs" {
  name_prefix = "bunshin-vpc-ep-ecs-"
  description = "Security group for VPC endpoints used by ECS tasks"
  vpc_id      = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-vpc-endpoint-for-ecs"
    Service = "vpc-endpoint"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "vpc_endpoint_for_ecs_ingress_broker" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.broker.id
  security_group_id        = aws_security_group.vpc_endpoint_for_ecs.id
  description              = "HTTPS from broker"
}

resource "aws_vpc_endpoint" "apne3_ecr_api" {
  vpc_id            = aws_vpc.apne3.id
  service_name      = "com.amazonaws.ap-northeast-3.ecr.api"
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.broker_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoint_for_ecs.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-ecr-api"
  })
}

resource "aws_vpc_endpoint" "apne3_ecr_dkr" {
  vpc_id            = aws_vpc.apne3.id
  service_name      = "com.amazonaws.ap-northeast-3.ecr.dkr"
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.broker_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoint_for_ecs.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-ecr-dkr"
  })
}

resource "aws_vpc_endpoint" "apne3_logs" {
  vpc_id            = aws_vpc.apne3.id
  service_name      = "com.amazonaws.ap-northeast-3.logs"
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.broker_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoint_for_ecs.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-logs"
  })
}

resource "aws_vpc_endpoint" "apne3_s3" {
  vpc_id       = aws_vpc.apne3.id
  service_name = "com.amazonaws.ap-northeast-3.s3"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.apne3_private.id]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne3-s3"
  })
}

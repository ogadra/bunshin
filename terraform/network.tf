resource "aws_vpc" "apne1" {
  provider = aws.apne1

  cidr_block           = local.apne1_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1"
  })
}

# Public subnets
resource "aws_subnet" "apne1_public" {
  provider = aws.apne1
  count    = length(local.azs_apne1)

  vpc_id            = aws_vpc.apne1.id
  cidr_block        = local.public_cidrs_apne1[count.index]
  availability_zone = local.azs_apne1[count.index]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-public-${local.azs_apne1[count.index]}"
  })
}

# Private subnets
resource "aws_subnet" "apne1_private" {
  provider = aws.apne1
  count    = length(local.azs_apne1)

  vpc_id            = aws_vpc.apne1.id
  cidr_block        = local.private_cidrs_apne1[count.index]
  availability_zone = local.azs_apne1[count.index]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-private-${local.azs_apne1[count.index]}"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "apne1" {
  provider = aws.apne1

  vpc_id = aws_vpc.apne1.id

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1"
  })
}

# Regional NAT Gateway
resource "aws_nat_gateway" "apne1" {
  provider = aws.apne1

  vpc_id            = aws_vpc.apne1.id
  availability_mode = "regional"

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-nat"
  })

  depends_on = [aws_internet_gateway.apne1]
}

# Public route table
resource "aws_route_table" "apne1_public" {
  provider = aws.apne1

  vpc_id = aws_vpc.apne1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.apne1.id
  }

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-public"
  })
}

resource "aws_route_table_association" "apne1_public" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1
  count    = length(local.azs_apne1)

  subnet_id      = aws_subnet.apne1_public[count.index].id
  route_table_id = aws_route_table.apne1_public.id
}

# Private route table
resource "aws_route_table" "apne1_private" {
  provider = aws.apne1

  vpc_id = aws_vpc.apne1.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.apne1.id
  }

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-private"
  })
}

resource "aws_route_table_association" "apne1_private" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1
  count    = length(local.azs_apne1)

  subnet_id      = aws_subnet.apne1_private[count.index].id
  route_table_id = aws_route_table.apne1_private.id
}

# VPC Gateway Endpoint for DynamoDB
resource "aws_vpc_endpoint" "apne1_dynamodb" {
  provider = aws.apne1

  vpc_id       = aws_vpc.apne1.id
  service_name = "com.amazonaws.ap-northeast-1.dynamodb"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.apne1_private.id]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-dynamodb"
  })
}

# VPC Interface Endpoints for ECS tasks
resource "aws_security_group" "apne1_vpc_endpoint_for_ecs" {
  provider = aws.apne1

  name_prefix = "bunshin-vpc-ep-ecs-"
  description = "Security group for VPC endpoints used by ECS tasks"
  vpc_id      = aws_vpc.apne1.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne1-vpc-endpoint-for-ecs"
    Service = "vpc-endpoint"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "apne1_vpc_endpoint_for_ecs_ingress" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1
  for_each = {
    nginx  = aws_security_group.nginx.id
    broker = aws_security_group.broker.id
    runner = aws_security_group.runner.id
  }

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.apne1_vpc_endpoint_for_ecs.id
  description              = "HTTPS from ${each.key}"
}

resource "aws_vpc_endpoint" "apne1_ecr_api" {
  provider = aws.apne1

  vpc_id            = aws_vpc.apne1.id
  service_name      = "com.amazonaws.ap-northeast-1.ecr.api"
  vpc_endpoint_type = "Interface"

  subnet_ids         = [aws_subnet.apne1_private[0].id]
  security_group_ids = [aws_security_group.apne1_vpc_endpoint_for_ecs.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-ecr-api"
  })
}

resource "aws_vpc_endpoint" "apne1_ecr_dkr" {
  provider = aws.apne1

  vpc_id            = aws_vpc.apne1.id
  service_name      = "com.amazonaws.ap-northeast-1.ecr.dkr"
  vpc_endpoint_type = "Interface"

  subnet_ids         = [aws_subnet.apne1_private[0].id]
  security_group_ids = [aws_security_group.apne1_vpc_endpoint_for_ecs.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-ecr-dkr"
  })
}

resource "aws_vpc_endpoint" "apne1_logs" {
  provider = aws.apne1

  vpc_id            = aws_vpc.apne1.id
  service_name      = "com.amazonaws.ap-northeast-1.logs"
  vpc_endpoint_type = "Interface"

  subnet_ids         = slice(aws_subnet.apne1_private[*].id, 1, 3)
  security_group_ids = [aws_security_group.apne1_vpc_endpoint_for_ecs.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-logs"
  })
}

# S3 Gateway Endpoint for ECR image layer storage
resource "aws_vpc_endpoint" "apne1_s3" {
  provider = aws.apne1

  vpc_id       = aws_vpc.apne1.id
  service_name = "com.amazonaws.ap-northeast-1.s3"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.apne1_private.id]

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-s3"
  })
}

# VPC Interface Endpoint for Bedrock Runtime
resource "aws_security_group" "apne1_bedrock_endpoint" {
  provider = aws.apne1

  name_prefix = "bunshin-bedrock-ep-"
  description = "Security group for Bedrock Runtime VPC endpoint"
  vpc_id      = aws_vpc.apne1.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne1-bedrock-endpoint"
    Service = "bedrock"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "apne1_bedrock_endpoint_ingress_runner" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.runner.id
  security_group_id        = aws_security_group.apne1_bedrock_endpoint.id
  description              = "HTTPS from runner"
}

resource "aws_vpc_endpoint" "apne1_bedrock_runtime" {
  provider = aws.apne1

  vpc_id            = aws_vpc.apne1.id
  service_name      = "com.amazonaws.ap-northeast-1.bedrock-runtime"
  vpc_endpoint_type = "Interface"

  subnet_ids         = aws_subnet.apne1_private[*].id
  security_group_ids = [aws_security_group.apne1_bedrock_endpoint.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-bedrock-runtime"
  })
}

# Restrict the default security group to deny all traffic
resource "aws_default_security_group" "apne1" {
  provider = aws.apne1

  vpc_id = aws_vpc.apne1.id

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-default"
  })
}

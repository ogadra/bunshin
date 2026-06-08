resource "aws_security_group_rule" "apne1_vpc_endpoint_for_ecs_ingress" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1
  for_each = {
    nginx  = aws_security_group.nginx.id
    runner = aws_security_group.runner.id
  }

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = module.apne1.vpc_endpoint_for_ecs_security_group_id
  description              = "HTTPS from ${each.key}"
}

resource "aws_security_group" "apne1_bedrock_endpoint" {
  provider = aws.apne1

  name_prefix = "bunshin-bedrock-ep-"
  description = "Security group for Bedrock Runtime VPC endpoint"
  vpc_id      = module.apne1.vpc_id

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

  vpc_id            = module.apne1.vpc_id
  service_name      = "com.amazonaws.ap-northeast-1.bedrock-runtime"
  vpc_endpoint_type = "Interface"

  subnet_ids         = module.apne1.ecs_subnet_ids
  security_group_ids = [aws_security_group.apne1_bedrock_endpoint.id]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "bunshin-apne1-bedrock-runtime"
  })
}

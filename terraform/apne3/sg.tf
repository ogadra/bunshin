resource "aws_security_group" "broker" {
  name_prefix = "bunshin-broker-"
  description = "Security group for broker ECS tasks"
  vpc_id      = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-broker"
    Service = "broker"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "broker_egress_dynamodb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.apne3_dynamodb.prefix_list_id]
  security_group_id = aws_security_group.broker.id
  description       = "HTTPS to DynamoDB VPC endpoint"
}

resource "aws_security_group_rule" "broker_egress_vpc_endpoint_for_ecs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoint_for_ecs.id
  security_group_id        = aws_security_group.broker.id
  description              = "HTTPS to VPC endpoints for ECS"
}

resource "aws_security_group_rule" "broker_egress_s3" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.apne3_s3.prefix_list_id]
  security_group_id = aws_security_group.broker.id
  description       = "HTTPS to S3 VPC endpoint"
}

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

resource "aws_security_group_rule" "broker_ingress_runner" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["broker"].port
  to_port                  = local.ecs_services["broker"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.runner.id
  security_group_id        = aws_security_group.broker.id
  description              = "HTTP from runner"
}

resource "aws_security_group_rule" "broker_egress_runner" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["runner"].port
  to_port                  = local.ecs_services["runner"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.runner.id
  security_group_id        = aws_security_group.broker.id
  description              = "HTTP to runner for healthcheck"
}

resource "aws_security_group_rule" "broker_ingress_nginx" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["broker"].port
  to_port                  = local.ecs_services["broker"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
  security_group_id        = aws_security_group.broker.id
  description              = "HTTP from nginx"
}

resource "aws_security_group_rule" "vpc_endpoint_for_ecs_egress" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  for_each = {
    nginx  = aws_security_group.nginx.id
    broker = aws_security_group.broker.id
    runner = aws_security_group.runner.id
  }

  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.apne3_vpc_endpoint_for_ecs.id
  security_group_id        = each.value
  description              = "HTTPS to VPC endpoints for ECS"
}

resource "aws_security_group_rule" "ecs_egress_s3" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  for_each = {
    nginx  = aws_security_group.nginx.id
    broker = aws_security_group.broker.id
    runner = aws_security_group.runner.id
  }

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.apne3_s3.prefix_list_id]
  security_group_id = each.value
  description       = "HTTPS to S3 VPC endpoint"
}

resource "aws_security_group" "external_alb" {
  name_prefix = "bunshin-external-alb-"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-external-alb"
    Service = "external-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "external_alb_ingress_https" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # trivy:ignore:AVD-AWS-0107 -- ALB is internet-facing, WAF restricts access via header validation
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.external_alb.id
  description       = "HTTPS from internet, WAF controlled"
}

resource "aws_security_group_rule" "external_alb_ingress_http" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV_AWS_260:HTTP port 80 is used for HTTPS redirect only
  # trivy:ignore:AVD-AWS-0107 -- HTTP listener redirects to HTTPS
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.external_alb.id
  description       = "HTTP from internet for HTTPS redirect"
}

resource "aws_security_group_rule" "external_alb_egress_nginx" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["nginx"].port
  to_port                  = local.ecs_services["nginx"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
  security_group_id        = aws_security_group.external_alb.id
  description              = "HTTP to nginx"
}

resource "aws_security_group" "internal_alb" {
  name_prefix = "bunshin-internal-alb-"
  description = "Security group for internal ALB"
  vpc_id      = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-internal-alb"
    Service = "internal-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "internal_alb_egress_nginx" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["nginx"].port
  to_port                  = local.ecs_services["nginx"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
  security_group_id        = aws_security_group.internal_alb.id
  description              = "HTTP to nginx"
}

resource "aws_security_group" "nginx" {
  name_prefix = "bunshin-nginx-"
  description = "Security group for nginx ECS tasks"
  vpc_id      = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-nginx"
    Service = "nginx"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "nginx_egress_broker" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["broker"].port
  to_port                  = local.ecs_services["broker"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.broker.id
  security_group_id        = aws_security_group.nginx.id
  description              = "HTTP to broker"
}

resource "aws_security_group_rule" "nginx_egress_runner" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["runner"].port
  to_port                  = local.ecs_services["runner"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.runner.id
  security_group_id        = aws_security_group.nginx.id
  description              = "HTTP to runner"
}

resource "aws_security_group_rule" "nginx_ingress_external_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["nginx"].port
  to_port                  = local.ecs_services["nginx"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.external_alb.id
  security_group_id        = aws_security_group.nginx.id
  description              = "HTTP from ALB"
}

resource "aws_security_group_rule" "nginx_ingress_internal_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["nginx"].port
  to_port                  = local.ecs_services["nginx"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.internal_alb.id
  security_group_id        = aws_security_group.nginx.id
  description              = "HTTP from internal ALB"
}

resource "aws_security_group" "runner" {
  name_prefix = "bunshin-runner-"
  description = "Security group for runner ECS tasks"
  vpc_id      = aws_vpc.apne3.id

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-runner"
    Service = "runner"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "runner_ingress_broker" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["runner"].port
  to_port                  = local.ecs_services["runner"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.broker.id
  security_group_id        = aws_security_group.runner.id
  description              = "HTTP from broker for healthcheck"
}

resource "aws_security_group_rule" "runner_ingress_nginx" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["runner"].port
  to_port                  = local.ecs_services["runner"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
  security_group_id        = aws_security_group.runner.id
  description              = "HTTP from nginx"
}

resource "aws_security_group_rule" "runner_egress_broker" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["broker"].port
  to_port                  = local.ecs_services["broker"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.broker.id
  security_group_id        = aws_security_group.runner.id
  description              = "HTTP to broker"
}

resource "aws_security_group_rule" "runner_egress_bedrock" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bedrock_endpoint.id
  security_group_id        = aws_security_group.runner.id
  description              = "HTTPS to Bedrock Runtime VPC endpoint"
}

# trivy:ignore:AVD-AWS-0104 -- runner requires outbound internet access
resource "aws_security_group_rule" "runner_egress_https" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.runner.id
  description       = "HTTPS to internet"
}

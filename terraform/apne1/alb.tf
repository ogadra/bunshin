# trivy:ignore:AVD-AWS-0053 -- target group uses HTTP, HTTPS terminates at ALB
resource "aws_lb_target_group" "external_nginx" {
  # checkov:skip=CKV_AWS_378:HTTPS terminates at ALB, target uses HTTP
  name        = "bunshin-external-nginx"
  port        = local.ecs_services["nginx"].port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.apne1.id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Service = "nginx"
  })
}

# trivy:ignore:AVD-AWS-0053 -- target group uses HTTP, HTTPS terminates at ALB
resource "aws_lb_target_group" "internal_nginx" {
  # checkov:skip=CKV_AWS_378:HTTPS terminates at ALB, target uses HTTP
  name        = "bunshin-internal-nginx"
  port        = local.ecs_services["nginx"].port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.apne1.id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Service = "nginx"
  })
}

# trivy:ignore:AVD-AWS-0053 -- CloudFront VPC origins reach this ALB over private networking
resource "aws_lb_target_group" "api_ingress_nginx" {
  # checkov:skip=CKV_AWS_378:CloudFront VPC origins reach this ALB over private networking
  name        = "bunshin-api-ingress-nginx"
  port        = local.ecs_services["nginx"].port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.apne1.id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Service = "nginx"
  })
}

# trivy:ignore:AVD-AWS-0054 -- ALB access logs are optional for initial deployment
# trivy:ignore:AVD-AWS-0053 -- ALB is intentionally internet-facing, protected by WAF
resource "aws_lb" "external" {
  # checkov:skip=CKV_AWS_91:ALB access logs are optional for initial deployment
  drop_invalid_header_fields = true
  # checkov:skip=CKV2_AWS_76:Log4j WAF rule is not needed, backend does not use Java
  # checkov:skip=CKV_AWS_150:Deletion protection is not needed for initial deployment
  name               = "bunshin-external"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external_alb.id]
  subnets            = aws_subnet.apne1_public[*].id

  tags = merge(local.common_tags, {
    Service = "external-alb"
  })
}

# trivy:ignore:AVD-AWS-0054 -- ALB access logs are optional for initial deployment
resource "aws_lb" "api_ingress" {
  # checkov:skip=CKV_AWS_91:ALB access logs are optional for initial deployment
  # checkov:skip=CKV2_AWS_20:CloudFront reaches this ALB through VPC origins over private networking
  drop_invalid_header_fields = true
  # checkov:skip=CKV_AWS_150:Deletion protection is not needed for initial deployment
  name               = "bunshin-api-ingress"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.api_ingress_alb.id]
  subnets            = local.ecs_subnet_ids

  tags = merge(local.common_tags, {
    Service = "api-ingress-alb"
  })
}

# trivy:ignore:AVD-AWS-0054 -- ALB access logs are optional for initial deployment
resource "aws_lb" "internal" {
  # checkov:skip=CKV_AWS_91:ALB access logs are optional for initial deployment
  drop_invalid_header_fields = true
  # checkov:skip=CKV_AWS_150:Deletion protection is not needed for initial deployment
  name               = "bunshin-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = local.ecs_subnet_ids

  tags = merge(local.common_tags, {
    Service = "internal-alb"
  })
}

# trivy:ignore:AVD-AWS-0054 -- CloudFront reaches this ALB through VPC origins over private networking
resource "aws_lb_listener" "api_ingress_http" {
  # checkov:skip=CKV_AWS_2:CloudFront reaches this ALB through VPC origins over private networking
  # checkov:skip=CKV_AWS_103:CloudFront reaches this ALB through VPC origins over private networking
  load_balancer_arn = aws_lb.api_ingress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_ingress_nginx.arn
  }

  tags = merge(local.common_tags, {
    Service = "api-ingress-alb"
  })
}

resource "aws_lb_listener" "external_https" {
  load_balancer_arn = aws_lb.external.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.external_nginx.arn
  }

  tags = merge(local.common_tags, {
    Service = "external-alb"
  })
}

resource "aws_lb_listener" "internal_https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_nginx.arn
  }

  tags = merge(local.common_tags, {
    Service = "internal-alb"
  })
}

resource "aws_lb_listener" "external_http" {
  # checkov:skip=CKV_AWS_2:HTTP listener is used for redirect to HTTPS only
  # checkov:skip=CKV_AWS_103:HTTP listener is used for redirect to HTTPS only
  load_balancer_arn = aws_lb.external.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.common_tags, {
    Service = "external-alb"
  })
}

resource "aws_wafv2_web_acl_association" "external_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  resource_arn = aws_lb.external.arn
  web_acl_arn  = aws_wafv2_web_acl.external_alb.arn
}

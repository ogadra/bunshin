resource "aws_security_group" "alb" {
  name_prefix = "bunshin-alb-"
  description = "Security group for ALB"
  vpc_id      = module.apne1.vpc_id

  tags = merge(local.common_tags, {
    Name    = "bunshin-alb"
    Service = "alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ALB inbound: HTTPS from internet, access controlled by WAF
# trivy:ignore:AVD-AWS-0107 -- ALB is internet-facing, WAF restricts access via header validation
resource "aws_security_group_rule" "alb_ingress_https" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet, WAF controlled"
}

# ALB inbound: HTTP from internet for HTTPS redirect
# trivy:ignore:AVD-AWS-0107 -- HTTP listener redirects to HTTPS
resource "aws_security_group_rule" "alb_ingress_http" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV_AWS_260:HTTP port 80 is used for HTTPS redirect only
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet for HTTPS redirect"
}

# ALB outbound: to nginx
resource "aws_security_group_rule" "alb_egress_nginx" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "egress"
  from_port                = local.ecs_services["nginx"].port
  to_port                  = local.ecs_services["nginx"].port
  protocol                 = "tcp"
  source_security_group_id = module.apne1.nginx_security_group_id
  security_group_id        = aws_security_group.alb.id
  description              = "HTTP to nginx"
}

resource "aws_security_group_rule" "nginx_ingress_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  type                     = "ingress"
  from_port                = local.ecs_services["nginx"].port
  to_port                  = local.ecs_services["nginx"].port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = module.apne1.nginx_security_group_id
  description              = "HTTP from ALB"
}

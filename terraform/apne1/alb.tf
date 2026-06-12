# trivy:ignore:AVD-AWS-0053 -- target group uses HTTP, HTTPS terminates at ALB
resource "aws_lb_target_group" "nginx" {
  # checkov:skip=CKV_AWS_378:HTTPS terminates at ALB, target uses HTTP
  name        = "bunshin-nginx"
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

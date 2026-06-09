data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_ecs_task_definition" "nginx" {
  # checkov:skip=CKV_AWS_336:nginx requires writable tmp directories
  family                   = "bunshin-nginx"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution["nginx"].arn
  task_role_arn            = aws_iam_role.task["nginx"].arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "nginx"
    image     = "${aws_ecr_repository.service["nginx"].repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = local.ecs_services["nginx"].port
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs["nginx"].name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "nginx"
      }
    }
  }])

  tags = merge(local.common_tags, {
    Service = "nginx"
  })
}

resource "aws_ecs_service" "nginx" {
  name                              = "bunshin-nginx"
  cluster                           = module.apne1.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.nginx.arn
  desired_count                     = 6
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets         = module.apne1.ecs_subnet_ids
    security_groups = [aws_security_group.nginx.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx"
    container_port   = local.ecs_services["nginx"].port
  }

  tags = merge(local.common_tags, {
    Service = "nginx"
  })
}

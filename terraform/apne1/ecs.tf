data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_ecs_cluster" "apne1" {
  name = "bunshin"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Service = "ecs"
  })
}

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
    image     = "${local.ecr_registry}/bunshin/nginx:latest"
    essential = true

    portMappings = [{
      containerPort = local.ecs_services["nginx"].port
      protocol      = "tcp"
    }]

    environment = [
      { name = "STACK_NAME", value = data.aws_region.current.id },
      { name = "INTERNAL_DOMAIN", value = var.domain_name },
    ]

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
  cluster                           = aws_ecs_cluster.apne1.id
  task_definition                   = aws_ecs_task_definition.nginx.arn
  desired_count                     = local.nginx_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60
  depends_on = [
    aws_iam_role_policy.execution_ecr["nginx"],
    aws_iam_role_policy.execution_logs["nginx"],
    aws_lb_listener.api_ingress_https,
    aws_lb_listener.internal_https,
  ]

  network_configuration {
    subnets         = local.ecs_subnet_ids
    security_groups = [aws_security_group.nginx.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_ingress_nginx.arn
    container_name   = "nginx"
    container_port   = local.ecs_services["nginx"].port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.internal_nginx.arn
    container_name   = "nginx"
    container_port   = local.ecs_services["nginx"].port
  }

  tags = merge(local.common_tags, {
    Service = "nginx"
  })
}

resource "aws_ecs_task_definition" "broker" {
  family                   = "bunshin-broker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution["broker"].arn
  task_role_arn            = aws_iam_role.task["broker"].arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name                   = "broker"
    image                  = "${local.ecr_registry}/bunshin/broker:latest"
    essential              = true
    readonlyRootFilesystem = true

    portMappings = [{
      containerPort = local.ecs_services["broker"].port
      protocol      = "tcp"
    }]

    environment = [
      { name = "AWS_REGION", value = data.aws_region.current.id },
      { name = "BUNSHIN_STACKS", value = join(",", var.bunshin_stacks) },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs["broker"].name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "broker"
      }
    }
  }])

  tags = merge(local.common_tags, {
    Service = "broker"
  })
}

resource "aws_ecs_service" "broker" {
  name            = "bunshin-broker"
  cluster         = aws_ecs_cluster.apne1.id
  task_definition = aws_ecs_task_definition.broker.arn
  desired_count   = local.broker_desired_count
  launch_type     = "FARGATE"
  depends_on = [
    aws_iam_role_policy.execution_ecr["broker"],
    aws_iam_role_policy.execution_logs["broker"],
    aws_iam_role_policy.broker_dynamodb,
  ]

  network_configuration {
    subnets         = local.ecs_subnet_ids
    security_groups = [aws_security_group.broker.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.broker.arn
  }

  tags = merge(local.common_tags, {
    Service = "broker"
  })
}

resource "aws_ecs_task_definition" "runner" {
  # checkov:skip=CKV_AWS_336:runner executes user commands and requires writable filesystem
  family                   = "bunshin-runner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution["runner"].arn
  task_role_arn            = aws_iam_role.task["runner"].arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "runner"
    image     = "${local.ecr_registry}/bunshin/runner:latest"
    essential = true

    portMappings = [{
      containerPort = local.ecs_services["runner"].port
      protocol      = "tcp"
    }]

    environment = [
      { name = "RUNNER_PORT", value = tostring(local.ecs_services["runner"].port) },
      { name = "BROKER_URL", value = "http://${aws_service_discovery_service.broker.name}.${aws_service_discovery_private_dns_namespace.internal.name}:${local.ecs_services["broker"].port}" },
      { name = "AWS_REGION", value = data.aws_region.current.id },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs["runner"].name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "runner"
      }
    }
  }])

  tags = merge(local.common_tags, {
    Service = "runner"
  })
}

resource "aws_ecs_service" "runner" {
  name            = "bunshin-runner"
  cluster         = aws_ecs_cluster.apne1.id
  task_definition = aws_ecs_task_definition.runner.arn
  desired_count   = local.runner_desired_count
  launch_type     = "FARGATE"
  depends_on = [
    aws_iam_role_policy.execution_ecr["runner"],
    aws_iam_role_policy.execution_logs["runner"],
    aws_iam_role_policy.runner_bedrock,
  ]

  network_configuration {
    subnets         = local.ecs_subnet_ids
    security_groups = [aws_security_group.runner.id]
  }

  tags = merge(local.common_tags, {
    Service = "runner"
  })
}

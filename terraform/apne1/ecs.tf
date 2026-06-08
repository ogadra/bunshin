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

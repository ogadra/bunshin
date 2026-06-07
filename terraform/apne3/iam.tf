data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "broker_task_execution" {
  name               = "bunshin-apne3-broker-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(local.common_tags, {
    Service = "broker"
  })
}

data "aws_iam_policy_document" "broker_execution_ecr" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [local.broker_repository_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "broker_execution_ecr" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name   = "bunshin-apne3-broker-execution-ecr"
  role   = aws_iam_role.broker_task_execution.id
  policy = data.aws_iam_policy_document.broker_execution_ecr.json
}

data "aws_iam_policy_document" "broker_execution_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.broker.arn}:*"]
  }
}

resource "aws_iam_role_policy" "broker_execution_logs" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name   = "bunshin-apne3-broker-execution-logs"
  role   = aws_iam_role.broker_task_execution.id
  policy = data.aws_iam_policy_document.broker_execution_logs.json
}

resource "aws_iam_role" "broker_task" {
  name               = "bunshin-apne3-broker-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(local.common_tags, {
    Service = "broker"
  })
}

data "aws_iam_policy_document" "broker_dynamodb" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      aws_dynamodb_table.runners_apne3.arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Query",
    ]
    resources = [
      "${aws_dynamodb_table.runners_apne3.arn}/index/session-index",
      "${aws_dynamodb_table.runners_apne3.arn}/index/idle-index",
    ]
  }
}

resource "aws_iam_role_policy" "broker_dynamodb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name   = "bunshin-apne3-broker-dynamodb"
  role   = aws_iam_role.broker_task.id
  policy = data.aws_iam_policy_document.broker_dynamodb.json
}

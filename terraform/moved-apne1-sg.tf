moved {
  from = aws_security_group.alb
  to   = module.apne1.aws_security_group.alb
}

moved {
  from = aws_security_group.nginx
  to   = module.apne1.aws_security_group.nginx
}

moved {
  from = aws_security_group.broker
  to   = module.apne1.aws_security_group.broker
}

moved {
  from = aws_security_group.runner
  to   = module.apne1.aws_security_group.runner
}

moved {
  from = aws_security_group_rule.alb_ingress_https
  to   = module.apne1.aws_security_group_rule.alb_ingress_https
}

moved {
  from = aws_security_group_rule.alb_ingress_http
  to   = module.apne1.aws_security_group_rule.alb_ingress_http
}

moved {
  from = aws_security_group_rule.alb_egress_nginx
  to   = module.apne1.aws_security_group_rule.alb_egress_nginx
}

moved {
  from = aws_security_group_rule.nginx_ingress_alb
  to   = module.apne1.aws_security_group_rule.nginx_ingress_alb
}

moved {
  from = aws_security_group_rule.nginx_egress_broker
  to   = module.apne1.aws_security_group_rule.nginx_egress_broker
}

moved {
  from = aws_security_group_rule.nginx_egress_runner
  to   = module.apne1.aws_security_group_rule.nginx_egress_runner
}

moved {
  from = aws_security_group_rule.broker_ingress_nginx
  to   = module.apne1.aws_security_group_rule.broker_ingress_nginx
}

moved {
  from = aws_security_group_rule.broker_ingress_runner
  to   = module.apne1.aws_security_group_rule.broker_ingress_runner
}

moved {
  from = aws_security_group_rule.broker_egress_runner
  to   = module.apne1.aws_security_group_rule.broker_egress_runner
}

moved {
  from = aws_security_group_rule.broker_egress_dynamodb
  to   = module.apne1.aws_security_group_rule.broker_egress_dynamodb
}

moved {
  from = aws_security_group_rule.runner_ingress_nginx
  to   = module.apne1.aws_security_group_rule.runner_ingress_nginx
}

moved {
  from = aws_security_group_rule.runner_ingress_broker
  to   = module.apne1.aws_security_group_rule.runner_ingress_broker
}

moved {
  from = aws_security_group_rule.runner_egress_broker
  to   = module.apne1.aws_security_group_rule.runner_egress_broker
}

moved {
  from = aws_security_group_rule.runner_egress_https
  to   = module.apne1.aws_security_group_rule.runner_egress_https
}

moved {
  from = aws_security_group_rule.vpc_endpoint_for_ecs_egress["nginx"]
  to   = module.apne1.aws_security_group_rule.vpc_endpoint_for_ecs_egress["nginx"]
}

moved {
  from = aws_security_group_rule.vpc_endpoint_for_ecs_egress["broker"]
  to   = module.apne1.aws_security_group_rule.vpc_endpoint_for_ecs_egress["broker"]
}

moved {
  from = aws_security_group_rule.vpc_endpoint_for_ecs_egress["runner"]
  to   = module.apne1.aws_security_group_rule.vpc_endpoint_for_ecs_egress["runner"]
}

moved {
  from = aws_security_group_rule.ecs_egress_s3["nginx"]
  to   = module.apne1.aws_security_group_rule.ecs_egress_s3["nginx"]
}

moved {
  from = aws_security_group_rule.ecs_egress_s3["broker"]
  to   = module.apne1.aws_security_group_rule.ecs_egress_s3["broker"]
}

moved {
  from = aws_security_group_rule.ecs_egress_s3["runner"]
  to   = module.apne1.aws_security_group_rule.ecs_egress_s3["runner"]
}

moved {
  from = aws_security_group_rule.runner_egress_bedrock
  to   = module.apne1.aws_security_group_rule.runner_egress_bedrock
}

moved {
  from = aws_vpc_endpoint.apne1_dynamodb
  to   = module.apne1.aws_vpc_endpoint.apne1_dynamodb
}

moved {
  from = aws_security_group.apne1_vpc_endpoint_for_ecs
  to   = module.apne1.aws_security_group.apne1_vpc_endpoint_for_ecs
}

moved {
  from = aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["nginx"]
  to   = module.apne1.aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["nginx"]
}

moved {
  from = aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["broker"]
  to   = module.apne1.aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["broker"]
}

moved {
  from = aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["runner"]
  to   = module.apne1.aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["runner"]
}

moved {
  from = aws_vpc_endpoint.apne1_ecr_api
  to   = module.apne1.aws_vpc_endpoint.apne1_ecr_api
}

moved {
  from = aws_vpc_endpoint.apne1_ecr_dkr
  to   = module.apne1.aws_vpc_endpoint.apne1_ecr_dkr
}

moved {
  from = aws_vpc_endpoint.apne1_logs
  to   = module.apne1.aws_vpc_endpoint.apne1_logs
}

moved {
  from = aws_vpc_endpoint.apne1_s3
  to   = module.apne1.aws_vpc_endpoint.apne1_s3
}

moved {
  from = aws_security_group.apne1_bedrock_endpoint
  to   = module.apne1.aws_security_group.apne1_bedrock_endpoint
}

moved {
  from = aws_security_group_rule.apne1_bedrock_endpoint_ingress_runner
  to   = module.apne1.aws_security_group_rule.apne1_bedrock_endpoint_ingress_runner
}

moved {
  from = aws_vpc_endpoint.apne1_bedrock_runtime
  to   = module.apne1.aws_vpc_endpoint.apne1_bedrock_runtime
}

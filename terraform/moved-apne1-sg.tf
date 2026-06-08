moved {
  from = aws_security_group.broker
  to   = module.apne1.aws_security_group.broker
}

moved {
  from = aws_security_group_rule.broker_egress_dynamodb
  to   = module.apne1.aws_security_group_rule.broker_egress_dynamodb
}

moved {
  from = aws_security_group_rule.vpc_endpoint_for_ecs_egress["broker"]
  to   = module.apne1.aws_security_group_rule.vpc_endpoint_for_ecs_egress
}

moved {
  from = aws_security_group_rule.ecs_egress_s3["broker"]
  to   = module.apne1.aws_security_group_rule.ecs_egress_s3
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
  from = aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress["broker"]
  to   = module.apne1.aws_security_group_rule.apne1_vpc_endpoint_for_ecs_ingress_broker
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

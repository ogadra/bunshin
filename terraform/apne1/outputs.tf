output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.apne1.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = local.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.apne1_public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.apne1_private[*].id
}

output "ecs_subnet_ids" {
  description = "IDs of the private subnets used by ECS services and interface endpoints"
  value       = local.ecs_subnet_ids
}

output "private_route_table_id" {
  description = "ID of the private route table, for gateway endpoint association"
  value       = aws_route_table.apne1_private.id
}

output "runners_table_arn" {
  description = "ARN of the regional runner-state DynamoDB table"
  value       = aws_dynamodb_table.runners_apne1.arn
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "nginx_security_group_id" {
  description = "ID of the nginx ECS task security group"
  value       = aws_security_group.nginx.id
}

output "broker_security_group_id" {
  description = "ID of the broker ECS task security group"
  value       = aws_security_group.broker.id
}

output "runner_security_group_id" {
  description = "ID of the runner ECS task security group"
  value       = aws_security_group.runner.id
}

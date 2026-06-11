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

output "broker_ecs_service_id" {
  description = "ID of the broker ECS service"
  value       = aws_ecs_service.broker.id
}

output "runner_ecs_service_id" {
  description = "ID of the runner ECS service"
  value       = aws_ecs_service.runner.id
}

output "nginx_ecs_service_id" {
  description = "ID of the nginx ECS service"
  value       = aws_ecs_service.nginx.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.apne1_private.id
}

output "nginx_security_group_id" {
  description = "ID of the nginx ECS task security group"
  value       = aws_security_group.nginx.id
}

output "nginx_target_group_arn" {
  description = "ARN of the nginx ALB target group"
  value       = aws_lb_target_group.nginx.arn
}

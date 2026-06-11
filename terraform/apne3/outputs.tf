output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.apne3.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = local.vpc_cidr
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
  value       = aws_route_table.apne3_private.id
}

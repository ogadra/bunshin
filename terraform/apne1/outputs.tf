output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.apne1.id
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
  value       = aws_route_table.apne1_private.id
}

output "external_alb_dns_name" {
  description = "DNS name of the external ALB"
  value       = aws_lb.external.dns_name
}

output "external_alb_zone_id" {
  description = "Canonical hosted zone ID of the external ALB"
  value       = aws_lb.external.zone_id
}

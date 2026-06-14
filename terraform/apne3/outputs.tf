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

output "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets"
  value       = aws_subnet.apne3_private[*].cidr_block
}

output "external_alb_dns_name" {
  description = "DNS name of the external ALB"
  value       = aws_lb.external.dns_name
}

output "external_alb_zone_id" {
  description = "Canonical hosted zone ID of the external ALB"
  value       = aws_lb.external.zone_id
}

output "api_ingress_alb_arn" {
  description = "ARN of the API ingress ALB"
  value       = aws_lb.api_ingress.arn
}

output "api_ingress_alb_dns_name" {
  description = "DNS name of the API ingress ALB"
  value       = aws_lb.api_ingress.dns_name
}

output "api_ingress_alb_zone_id" {
  description = "Canonical hosted zone ID of the API ingress ALB"
  value       = aws_lb.api_ingress.zone_id
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB"
  value       = aws_lb.internal.dns_name
}

output "internal_alb_zone_id" {
  description = "Canonical hosted zone ID of the internal ALB"
  value       = aws_lb.internal.zone_id
}

output "internal_alb_security_group_id" {
  description = "ID of the internal ALB security group"
  value       = aws_security_group.internal_alb.id
}

output "nginx_security_group_id" {
  description = "ID of the nginx security group"
  value       = aws_security_group.nginx.id
}

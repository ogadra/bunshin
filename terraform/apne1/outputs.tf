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

output "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets"
  value       = aws_subnet.apne1_private[*].cidr_block
}

output "api_ingress_alb_arn" {
  description = "ARN of the API ingress ALB"
  value       = aws_lb.api_ingress.arn
}

output "internal_route53_zone_id" {
  description = "ID of the internal Route 53 private hosted zone"
  value       = aws_route53_zone.internal.zone_id
}

output "internal_alb_security_group_id" {
  description = "ID of the internal ALB security group"
  value       = aws_security_group.internal_alb.id
}

output "nginx_security_group_id" {
  description = "ID of the nginx security group"
  value       = aws_security_group.nginx.id
}

output "static_bucket_arn" {
  description = "ARN of the static asset bucket"
  value       = aws_s3_bucket.static.arn
}

output "static_bucket_regional_domain_name" {
  description = "Regional domain name of the static asset bucket"
  value       = aws_s3_bucket.static.bucket_regional_domain_name
}

output "static_bucket_versioning_status" {
  description = "Versioning status of the static asset bucket"
  value       = aws_s3_bucket_versioning.static.versioning_configuration[0].status
}

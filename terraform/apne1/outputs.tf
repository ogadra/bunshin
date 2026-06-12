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

output "ecs_subnet_ids" {
  description = "IDs of the private subnets used by ECS services and interface endpoints"
  value       = local.ecs_subnet_ids
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.apne1.id
}

output "broker_ecs_service_id" {
  description = "ID of the broker ECS service"
  value       = aws_ecs_service.broker.id
}

output "runner_ecs_service_id" {
  description = "ID of the runner ECS service"
  value       = aws_ecs_service.runner.id
}

output "private_route_table_id" {
  description = "ID of the private route table, for gateway endpoint association"
  value       = aws_route_table.apne1_private.id
}

output "broker_security_group_id" {
  description = "ID of the broker ECS task security group"
  value       = aws_security_group.broker.id
}

output "runner_security_group_id" {
  description = "ID of the runner ECS task security group"
  value       = aws_security_group.runner.id
}

output "vpc_endpoint_for_ecs_security_group_id" {
  description = "ID of the VPC endpoint security group used by ECS tasks"
  value       = aws_security_group.apne1_vpc_endpoint_for_ecs.id
}

output "s3_prefix_list_id" {
  description = "Prefix list ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.apne1_s3.prefix_list_id
}

output "nginx_task_execution_role_arn" {
  description = "ARN of the nginx ECS task execution role"
  value       = aws_iam_role.ecs_task_execution["nginx"].arn
}

output "nginx_task_role_arn" {
  description = "ARN of the nginx ECS task role"
  value       = aws_iam_role.task["nginx"].arn
}

output "nginx_log_group_name" {
  description = "Name of the nginx ECS log group"
  value       = aws_cloudwatch_log_group.ecs["nginx"].name
}

output "nginx_security_group_id" {
  description = "ID of the nginx ECS task security group"
  value       = aws_security_group.nginx.id
}

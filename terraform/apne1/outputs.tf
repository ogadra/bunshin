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

output "private_route_table_id" {
  description = "ID of the private route table, for gateway endpoint association"
  value       = aws_route_table.apne1_private.id
}

output "broker_security_group_id" {
  description = "ID of the broker ECS task security group"
  value       = aws_security_group.broker.id
}

output "vpc_endpoint_for_ecs_security_group_id" {
  description = "ID of the VPC endpoint security group used by ECS tasks"
  value       = aws_security_group.apne1_vpc_endpoint_for_ecs.id
}

output "s3_prefix_list_id" {
  description = "Prefix list ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.apne1_s3.prefix_list_id
}

output "broker_service_discovery_name" {
  description = "Name of the broker service discovery service"
  value       = aws_service_discovery_service.broker.name
}

output "private_dns_namespace_name" {
  description = "Name of the private DNS namespace"
  value       = aws_service_discovery_private_dns_namespace.internal.name
}

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

output "private_route_table_id" {
  description = "ID of the private route table, for gateway endpoint association"
  value       = aws_route_table.apne1_private.id
}

output "runners_table_arn" {
  description = "ARN of the regional runner-state DynamoDB table"
  value       = aws_dynamodb_table.runners_apne1.arn
}

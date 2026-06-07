output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.apne3.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.apne3_public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.apne3_private[*].id
}

output "runners_table_arn" {
  description = "ARN of the regional runner-state DynamoDB table"
  value       = aws_dynamodb_table.runners_apne3.arn
}

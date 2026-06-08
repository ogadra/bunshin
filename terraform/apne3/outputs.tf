output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.apne3.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = local.vpc_cidr
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.apne3_private.id
}

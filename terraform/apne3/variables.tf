variable "peer_vpc_cidr" {
  description = "CIDR block of the peer VPC reachable through VPC peering"
  type        = string
}

variable "vpc_peering_connection_id" {
  description = "ID of the accepted VPC peering connection used for private subnet routes"
  type        = string
}

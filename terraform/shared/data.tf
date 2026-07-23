data "aws_vpn_gateway" "apne1" {
  provider = aws.apne1

  filter {
    name   = "tag:Service"
    values = ["bunshin-vpn-apne1"]
  }
}

data "aws_vpn_gateway" "apne3" {
  provider = aws.apne3

  filter {
    name   = "tag:Service"
    values = ["bunshin-vpn-apne3"]
  }
}

data "aws_route_tables" "apne1_private" {
  provider = aws.apne1

  filter {
    name   = "tag:Name"
    values = ["bunshin-apne1-private"]
  }
}

data "aws_route_tables" "apne3_private" {
  provider = aws.apne3

  filter {
    name   = "tag:Name"
    values = ["bunshin-apne3-private"]
  }
}

data "google_compute_ha_vpn_gateway" "google_cloud" {
  for_each = local.google_cloud_regions

  name   = "bunshin-ha-vpn-${each.key}"
  region = each.value
}

data "google_compute_network" "google_cloud" {
  for_each = local.google_cloud_regions

  name = "bunshin-${each.key}-vpc"
}

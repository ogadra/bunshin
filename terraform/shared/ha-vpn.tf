locals {
  vpn_pairs = {
    apne1-asne1 = { aws = "apne1", gcp = "asne1" }
    apne1-asne2 = { aws = "apne1", gcp = "asne2" }
    apne3-asne1 = { aws = "apne3", gcp = "asne1" }
    apne3-asne2 = { aws = "apne3", gcp = "asne2" }
  }

  gcp_regions = {
    asne1 = "asia-northeast1"
    asne2 = "asia-northeast2"
  }

  # AWS VGW default ASN (apne1/apne3 の aws_vpn_gateway は amazon_side_asn 未指定のため 64512)
  aws_vgw_asn = 64512

  # GCP Cloud Router ASN。region ごとに別 ASN を採番して同一 AWS 側から見た BGP session を区別する
  gcp_router_asn = {
    asne1 = 64520
    asne2 = 64521
  }

  vpn_interfaces_all = { for e in flatten([
    for pk, pv in local.vpn_pairs : [
      for i in [0, 1] : {
        key       = "${pk}-if${i}"
        pair_key  = pk
        aws       = pv.aws
        gcp       = pv.gcp
        interface = i
      }
    ]
    ]) : e.key => e
  }

  vpn_interfaces_apne1 = { for k, v in local.vpn_interfaces_all : k => v if v.aws == "apne1" }
  vpn_interfaces_apne3 = { for k, v in local.vpn_interfaces_all : k => v if v.aws == "apne3" }

  vpn_tunnels_all = { for e in flatten([
    for ik, iv in local.vpn_interfaces_all : [
      for t in [1, 2] : {
        key           = "${ik}-t${t}"
        pair_key      = iv.pair_key
        interface_key = ik
        gcp           = iv.gcp
        interface     = iv.interface
        tunnel        = t
      }
    ]
    ]) : e.key => e
  }

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }

  common_labels = {
    project    = "bunshin"
    managed_by = "terraform"
  }

  aws_vpn_connections = merge(
    aws_vpn_connection.apne1,
    aws_vpn_connection.apne3,
  )
}

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

data "google_compute_ha_vpn_gateway" "gcp" {
  for_each = local.gcp_regions

  name   = "bunshin-ha-vpn-${each.key}"
  region = each.value
}

data "google_compute_network" "gcp" {
  for_each = local.gcp_regions

  name = "bunshin-${each.key}-vpc"
}

resource "aws_customer_gateway" "apne1" {
  provider = aws.apne1
  for_each = local.vpn_interfaces_apne1

  bgp_asn    = local.gcp_router_asn[each.value.gcp]
  ip_address = data.google_compute_ha_vpn_gateway.gcp[each.value.gcp].vpn_interfaces[each.value.interface].ip_address
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "bunshin-cgw-${each.key}"
  })
}

resource "aws_customer_gateway" "apne3" {
  provider = aws.apne3
  for_each = local.vpn_interfaces_apne3

  bgp_asn    = local.gcp_router_asn[each.value.gcp]
  ip_address = data.google_compute_ha_vpn_gateway.gcp[each.value.gcp].vpn_interfaces[each.value.interface].ip_address
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "bunshin-cgw-${each.key}"
  })
}

resource "aws_vpn_connection" "apne1" {
  provider = aws.apne1
  for_each = local.vpn_interfaces_apne1

  vpn_gateway_id      = data.aws_vpn_gateway.apne1.id
  customer_gateway_id = aws_customer_gateway.apne1[each.key].id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = merge(local.common_tags, {
    Name = "bunshin-vpn-${each.key}"
  })
}

resource "aws_vpn_connection" "apne3" {
  provider = aws.apne3
  for_each = local.vpn_interfaces_apne3

  vpn_gateway_id      = data.aws_vpn_gateway.apne3.id
  customer_gateway_id = aws_customer_gateway.apne3[each.key].id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = merge(local.common_tags, {
    Name = "bunshin-vpn-${each.key}"
  })
}

resource "aws_vpn_gateway_route_propagation" "apne1" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1
  for_each = toset(data.aws_route_tables.apne1_private.ids)

  vpn_gateway_id = data.aws_vpn_gateway.apne1.id
  route_table_id = each.value
}

resource "aws_vpn_gateway_route_propagation" "apne3" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne3
  for_each = toset(data.aws_route_tables.apne3_private.ids)

  vpn_gateway_id = data.aws_vpn_gateway.apne3.id
  route_table_id = each.value
}

resource "google_compute_router" "vpn" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = local.gcp_regions

  name    = "bunshin-vpn-${each.key}-router"
  region  = each.value
  network = data.google_compute_network.gcp[each.key].id

  bgp {
    asn = local.gcp_router_asn[each.key]
  }
}

resource "google_compute_external_vpn_gateway" "cross_cloud" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = local.vpn_pairs

  name            = "bunshin-cross-cloud-${each.key}"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  description     = "AWS VGW tunnel endpoints for ${each.key}"

  interface {
    id         = 0
    ip_address = local.aws_vpn_connections["${each.key}-if0"].tunnel1_address
  }
  interface {
    id         = 1
    ip_address = local.aws_vpn_connections["${each.key}-if0"].tunnel2_address
  }
  interface {
    id         = 2
    ip_address = local.aws_vpn_connections["${each.key}-if1"].tunnel1_address
  }
  interface {
    id         = 3
    ip_address = local.aws_vpn_connections["${each.key}-if1"].tunnel2_address
  }
}

resource "google_compute_vpn_tunnel" "cross_cloud" {
  for_each = local.vpn_tunnels_all

  name                            = "bunshin-vpn-${each.key}"
  region                          = local.gcp_regions[each.value.gcp]
  vpn_gateway                     = data.google_compute_ha_vpn_gateway.gcp[each.value.gcp].id
  vpn_gateway_interface           = each.value.interface
  peer_external_gateway           = google_compute_external_vpn_gateway.cross_cloud[each.value.pair_key].id
  peer_external_gateway_interface = each.value.interface * 2 + (each.value.tunnel - 1)
  router                          = google_compute_router.vpn[each.value.gcp].id
  ike_version                     = 2

  shared_secret = each.value.tunnel == 1 ? (
    local.aws_vpn_connections[each.value.interface_key].tunnel1_preshared_key
    ) : (
    local.aws_vpn_connections[each.value.interface_key].tunnel2_preshared_key
  )

  labels = local.common_labels
}

resource "google_compute_router_interface" "vpn" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = local.vpn_tunnels_all

  name       = "bunshin-vpn-${each.key}"
  router     = google_compute_router.vpn[each.value.gcp].name
  region     = local.gcp_regions[each.value.gcp]
  vpn_tunnel = google_compute_vpn_tunnel.cross_cloud[each.key].name

  ip_range = each.value.tunnel == 1 ? (
    format("%s/30", local.aws_vpn_connections[each.value.interface_key].tunnel1_cgw_inside_address)
    ) : (
    format("%s/30", local.aws_vpn_connections[each.value.interface_key].tunnel2_cgw_inside_address)
  )
}

resource "google_compute_router_peer" "vpn" {
  # checkov:skip=CKV_BUNSHIN_2:Resource does not support labels
  for_each = local.vpn_tunnels_all

  name      = "bunshin-vpn-${each.key}"
  router    = google_compute_router.vpn[each.value.gcp].name
  region    = local.gcp_regions[each.value.gcp]
  interface = google_compute_router_interface.vpn[each.key].name
  peer_asn  = local.aws_vgw_asn

  peer_ip_address = each.value.tunnel == 1 ? (
    local.aws_vpn_connections[each.value.interface_key].tunnel1_vgw_inside_address
    ) : (
    local.aws_vpn_connections[each.value.interface_key].tunnel2_vgw_inside_address
  )
}

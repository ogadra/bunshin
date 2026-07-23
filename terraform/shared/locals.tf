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

  # AWS default は transform set が多く、SA payload の fragmentation で GCP HA VPN の rekey が失敗する。
  # lifetime は AWS 上限 (P1 28800 / P2 3600) を使う。GCP HA VPN の固定値より短いため rekey は AWS 側発火。
  # https://cloud.google.com/network-connectivity/docs/vpn/how-to/connect-ha-vpn-aws-peer-gateway
  aws_vpn_ike_proposal = {
    ike_versions            = ["ikev2"]
    phase1_encryption       = ["AES256"]
    phase1_integrity        = ["SHA2-256"]
    phase1_dh_group         = [14]
    phase1_lifetime_seconds = 28800
    phase2_encryption       = ["AES256"]
    phase2_integrity        = ["SHA2-256"]
    phase2_dh_group         = [14]
    phase2_lifetime_seconds = 3600
  }
}

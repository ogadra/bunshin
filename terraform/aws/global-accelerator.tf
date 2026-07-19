resource "aws_globalaccelerator_accelerator" "api_ingress" {
  # checkov:skip=CKV_AWS_75:Flow logs are not required for the initial API ingress deployment
  name    = "bunshin-api-ingress"
  enabled = true

  ip_address_type = "IPV4"

  tags = merge(local.common_tags, {
    Name    = "bunshin-api-ingress"
    Service = "api-ingress"
  })
}

resource "aws_globalaccelerator_listener" "api_ingress_https" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  accelerator_arn = aws_globalaccelerator_accelerator.api_ingress.arn
  protocol        = "TCP"

  port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "api_ingress_apne1" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  listener_arn            = aws_globalaccelerator_listener.api_ingress_https.arn
  endpoint_group_region   = "ap-northeast-1"
  traffic_dial_percentage = 100

  endpoint_configuration {
    client_ip_preservation_enabled = true
    endpoint_id                    = module.apne1.api_ingress_alb_arn
    weight                         = 128
  }
}

resource "aws_globalaccelerator_endpoint_group" "api_ingress_apne3" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  listener_arn            = aws_globalaccelerator_listener.api_ingress_https.arn
  endpoint_group_region   = "ap-northeast-3"
  traffic_dial_percentage = 100

  endpoint_configuration {
    client_ip_preservation_enabled = true
    endpoint_id                    = module.apne3.api_ingress_alb_arn
    weight                         = 128
  }
}

# port-forward で ap-northeast-1 の runner に着弾させたい要求は、stack 固定の
# listener (8443) を経由させる。ALB は既存 443 で受けるので port_override で 443
# に付け替え、endpoint group には apne1 の ALB だけを載せる。
resource "aws_globalaccelerator_listener" "api_ingress_apne1_pf" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  accelerator_arn = aws_globalaccelerator_accelerator.api_ingress.arn
  protocol        = "TCP"

  port_range {
    from_port = 8443
    to_port   = 8443
  }
}

resource "aws_globalaccelerator_endpoint_group" "api_ingress_apne1_pf" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  listener_arn            = aws_globalaccelerator_listener.api_ingress_apne1_pf.arn
  endpoint_group_region   = "ap-northeast-1"
  traffic_dial_percentage = 100

  endpoint_configuration {
    client_ip_preservation_enabled = true
    endpoint_id                    = module.apne1.api_ingress_alb_arn
    weight                         = 128
  }

  port_override {
    listener_port = 8443
    endpoint_port = 443
  }
}

# ap-northeast-3 に固定させる port-forward listener。9443 は 8443 と衝突しないよう別に取る。
resource "aws_globalaccelerator_listener" "api_ingress_apne3_pf" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  accelerator_arn = aws_globalaccelerator_accelerator.api_ingress.arn
  protocol        = "TCP"

  port_range {
    from_port = 9443
    to_port   = 9443
  }
}

resource "aws_globalaccelerator_endpoint_group" "api_ingress_apne3_pf" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  listener_arn            = aws_globalaccelerator_listener.api_ingress_apne3_pf.arn
  endpoint_group_region   = "ap-northeast-3"
  traffic_dial_percentage = 100

  endpoint_configuration {
    client_ip_preservation_enabled = true
    endpoint_id                    = module.apne3.api_ingress_alb_arn
    weight                         = 128
  }

  port_override {
    listener_port = 9443
    endpoint_port = 443
  }
}

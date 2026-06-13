resource "aws_wafv2_web_acl" "external_alb" {
  # checkov:skip=CKV_AWS_192:Log4j protection is not needed, backend does not use Java
  # checkov:skip=CKV2_AWS_31:WAF logging is not needed for initial deployment
  name  = "bunshin-apne1-external-alb-waf"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "allow-proxy-secret"
    priority = 1

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        search_string = var.proxy_secret

        field_to_match {
          single_header {
            name = "x-proxy-secret"
          }
        }

        text_transformation {
          priority = 0
          type     = "NONE"
        }

        positional_constraint = "EXACTLY"
      }
    }

    visibility_config {
      sampled_requests_enabled   = false
      cloudwatch_metrics_enabled = true
      metric_name                = "bunshin-allow-proxy-secret"
    }
  }

  visibility_config {
    sampled_requests_enabled   = false
    cloudwatch_metrics_enabled = true
    metric_name                = "bunshin-apne1-external-alb-waf"
  }

  tags = merge(local.common_tags, {
    Service = "external-alb"
  })
}

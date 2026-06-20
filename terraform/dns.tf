data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "cloudfront" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_ipv6" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_ingress_origin" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV2_AWS_23:Alias targets Global Accelerator for health-aware API ingress

  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_ingress_origin_domain_name
  type    = "A"

  alias {
    name                   = aws_globalaccelerator_accelerator.api_ingress.dns_name
    zone_id                = aws_globalaccelerator_accelerator.api_ingress.hosted_zone_id
    evaluate_target_health = false
  }
}

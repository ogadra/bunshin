data "aws_route53_zone" "main" {
  name         = join(".", slice(split(".", var.domain_name), 1, length(split(".", var.domain_name))))
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

resource "aws_route53_zone_association" "apne1_internal_apne3" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id    = module.apne1.internal_route53_zone_id
  vpc_id     = module.apne3.vpc_id
  vpc_region = "ap-northeast-3"
}

resource "aws_route53_zone_association" "apne3_internal_apne1" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id    = module.apne3.internal_route53_zone_id
  vpc_id     = module.apne1.vpc_id
  vpc_region = "ap-northeast-1"
}

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

resource "aws_route53_record" "api_ingress_origin" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  # checkov:skip=CKV2_AWS_23:Alias targets the regional API ingress ALB through module outputs
  for_each = local.api_ingress_origins

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.domain_name
  type    = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_zone" "apne1_internal" {
  name = "apne1-internal.${var.domain_name}"

  vpc {
    vpc_id     = module.apne1.vpc_id
    vpc_region = "ap-northeast-1"
  }

  tags = merge(local.common_tags, {
    Service = "internal-alb"
  })
}

resource "aws_route53_zone_association" "apne1_internal_apne3" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id    = aws_route53_zone.apne1_internal.zone_id
  vpc_id     = module.apne3.vpc_id
  vpc_region = "ap-northeast-3"
}

resource "aws_route53_record" "apne1_internal_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id = aws_route53_zone.apne1_internal.zone_id
  name    = aws_route53_zone.apne1_internal.name
  type    = "A"

  alias {
    name                   = module.apne1.internal_alb_dns_name
    zone_id                = module.apne1.internal_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_zone" "apne3_internal" {
  name = "apne3-internal.${var.domain_name}"

  vpc {
    vpc_id     = module.apne3.vpc_id
    vpc_region = "ap-northeast-3"
  }

  tags = merge(local.common_tags, {
    Service = "internal-alb"
  })
}

resource "aws_route53_zone_association" "apne3_internal_apne1" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id    = aws_route53_zone.apne3_internal.zone_id
  vpc_id     = module.apne1.vpc_id
  vpc_region = "ap-northeast-1"
}

resource "aws_route53_record" "apne3_internal_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id = aws_route53_zone.apne3_internal.zone_id
  name    = aws_route53_zone.apne3_internal.name
  type    = "A"

  alias {
    name                   = module.apne3.internal_alb_dns_name
    zone_id                = module.apne3.internal_alb_zone_id
    evaluate_target_health = true
  }
}

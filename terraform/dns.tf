# Route 53 hosted zone lookup
data "aws_route53_zone" "main" {
  name         = join(".", slice(split(".", var.domain_name), 1, length(split(".", var.domain_name))))
  private_zone = false
}

# DNS alias record pointing to ALB
resource "aws_route53_record" "alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.apne1.external_alb_dns_name
    zone_id                = module.apne1.external_alb_zone_id
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

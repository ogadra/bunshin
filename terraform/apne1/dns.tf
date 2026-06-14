resource "aws_route53_zone" "internal" {
  name = "apne1-internal.${var.domain_name}"

  vpc {
    vpc_id     = aws_vpc.apne1.id
    vpc_region = "ap-northeast-1"
  }

  tags = merge(local.common_tags, {
    Service = "internal-alb"
  })
}

resource "aws_route53_record" "internal_alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  zone_id = aws_route53_zone.internal.zone_id
  name    = aws_route53_zone.internal.name
  type    = "A"

  alias {
    name                   = aws_lb.internal.dns_name
    zone_id                = aws_lb.internal.zone_id
    evaluate_target_health = true
  }
}

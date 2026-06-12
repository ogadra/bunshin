resource "aws_wafv2_web_acl_association" "alb" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  resource_arn = aws_lb.main.arn
  web_acl_arn  = module.apne1.external_waf_web_acl_arn
}

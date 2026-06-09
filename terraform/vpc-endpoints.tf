resource "aws_security_group_rule" "apne1_vpc_endpoint_for_ecs_ingress" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  provider = aws.apne1
  for_each = {
    nginx = aws_security_group.nginx.id
  }

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = module.apne1.vpc_endpoint_for_ecs_security_group_id
  description              = "HTTPS from ${each.key}"
}

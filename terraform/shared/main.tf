# 他 vendor の resource は provider data resource で参照する。terraform_remote_state を使うと
# vendor 間で tfstate schema に依存が生じるため
# tflint-ignore: terraform_unused_declarations
data "aws_route53_zone" "apex" {
  name         = var.domain_name
  private_zone = false
}

# tflint-ignore: terraform_unused_declarations
data "google_project" "current" {}

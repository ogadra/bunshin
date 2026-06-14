data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_region" "apne1" {
  provider = aws.apne1
}

data "aws_region" "apne3" {
  provider = aws.apne3
}

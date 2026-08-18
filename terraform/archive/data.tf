data "aws_caller_identity" "current" {
  provider = aws.apne1
}

data "google_project" "current" {}

terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.40"
    }
  }
}

# aws profile と google project は AWS_PROFILE / ADC (GOOGLE_CLOUD_PROJECT) の env から解決させ、
# 認証情報を tfvars に置かない (aws / google-cloud vendor と同じ方針)
provider "aws" {
  region = "ap-northeast-1"
}

provider "google" {}

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
    # google_project_service_identityはGA providerに無いbeta専用resource
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.40"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = var.aws_profile
}

# project は gcloud ADC / GOOGLE_CLOUD_PROJECT の環境から解決させ、project ID を tfvars 化しない
provider "google" {}

provider "google-beta" {}

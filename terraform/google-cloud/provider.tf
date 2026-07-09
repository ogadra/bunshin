# Terraform と Google Cloud プロバイダのバージョン制約
terraform {
  required_version = ">= 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.39"
    }
  }
}

# project は gcloud ADC / GOOGLE_CLOUD_PROJECT の環境から解決させ、project ID を tfvars 化しない
provider "google" {}

provider "google-beta" {}

provider "google" {
  alias  = "asne1"
  region = "asia-northeast1"
}

provider "google" {
  alias  = "asne2"
  region = "asia-northeast2"
}

data "google_project" "current" {}

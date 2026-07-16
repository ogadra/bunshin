terraform {
  required_version = ">= 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

# project は gcloud ADC / GOOGLE_CLOUD_PROJECT の環境から解決させ、project ID を tfvars 化しない
provider "google" {}

provider "google" {
  alias  = "asne1"
  region = "asia-northeast1"
}

provider "google" {
  alias  = "asne2"
  region = "asia-northeast2"
}

data "google_project" "current" {}

data "google_client_config" "default" {}

# host は fleet の Connect Gateway endpoint。cluster の endpoint / CA を直接参照すると provider 設定が
# 同一 apply で作成されるリソースに依存し初回 plan が壊れるため、fleet membership URL で終端する
# (Connect Gateway が TLS を終端するので CA 不要)。path は project number (project ID ではない)。
provider "kubernetes" {
  alias = "asne1"
  host  = "https://connectgateway.googleapis.com/v1/projects/${data.google_project.current.number}/locations/global/gkeMemberships/bunshin-asne1"
  token = data.google_client_config.default.access_token
}

provider "kubernetes" {
  alias = "asne2"
  host  = "https://connectgateway.googleapis.com/v1/projects/${data.google_project.current.number}/locations/global/gkeMemberships/bunshin-asne2"
  token = data.google_client_config.default.access_token
}

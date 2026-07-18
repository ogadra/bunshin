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
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.4"
    }
  }
}

# project は gcloud ADC / GOOGLE_CLOUD_PROJECT の環境から解決させ、project ID を tfvars 化しない
provider "google" {}

provider "google" {
  alias   = "asne1"
  region  = "asia-northeast1"
  project = data.google_project.current.project_id
}

provider "google" {
  alias   = "asne2"
  region  = "asia-northeast2"
  project = data.google_project.current.project_id
}

data "google_project" "current" {}

data "google_client_config" "default" {}

data "google_client_openid_userinfo" "me" {}

# hostはfleetのConnect Gateway endpoint。clusterのendpoint/CAを直接参照するとprovider設定が
# 同一applyで作成されるリソースに依存し初回planが壊れるため、fleet membership URLで終端する
# (Connect GatewayがTLSを終端するのでCA不要)。pathはproject number (project IDではない)。
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

# kubectl_manifestを使うのは初回applyでcluster未作成の状態でもplanが通るため。kubernetes_manifest
# はplan時にAPI discoveryでclusterへ接続してGVKを解決するのでinitial applyで詰む。
# load_config_file=falseでkubeconfig参照を無効化し、hostとtokenだけで駆動する
provider "kubectl" {
  alias            = "asne1"
  host             = "https://connectgateway.googleapis.com/v1/projects/${data.google_project.current.number}/locations/global/gkeMemberships/bunshin-asne1"
  token            = data.google_client_config.default.access_token
  load_config_file = false
}

provider "kubectl" {
  alias            = "asne2"
  host             = "https://connectgateway.googleapis.com/v1/projects/${data.google_project.current.number}/locations/global/gkeMemberships/bunshin-asne2"
  token            = data.google_client_config.default.access_token
  load_config_file = false
}

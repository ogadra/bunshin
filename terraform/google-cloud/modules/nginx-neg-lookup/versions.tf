terraform {
  required_version = ">= 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.40"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.4"
    }
  }
}

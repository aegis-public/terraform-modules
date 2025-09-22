terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 7.1.1"
    }
    helm = {
      source = "hashicorp/helm"
      version = "~> 3.0.2"
    }
  }
}

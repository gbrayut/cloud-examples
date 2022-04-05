# https://www.terraform.io/language/settings/backends/gcs
terraform {
  backend "gcs" {
    bucket  = "tf-state-clusterseiwzln"
    prefix  = "terraform/test/state"
  }
}

provider "google" {
  project     = "demo2021-310119"
  region      = "us-central1"
  zone        = "us-central1-c"
  
}

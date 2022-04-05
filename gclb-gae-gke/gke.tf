# From https://learn.hashicorp.com/tutorials/terraform/gke

# Setup GKE project+vpc+cluster
resource "google_project" "my_gke_project" {
  auto_create_network = false
  name                = "gregbray-gke"
  project_id          = "gregbray-gke"
  folder_id           = var.my_folder_id
  billing_account     = var.my_billing_account
  skip_delete         = true
}

resource "google_compute_network" "vpc" {
  name                    = "gke-vpc"
  auto_create_subnetworks = "false"
  project                 = google_project.my_gke_project.name
}

resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  project       = google_project.my_gke_project.name
  ip_cidr_range = "10.10.0.0/24"

  depends_on = [
    google_compute_network.vpc
  ]
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster
resource "google_container_cluster" "gke" {
  name     = "gke"
  location = var.region
  project  = google_project.my_gke_project.name

  remove_default_node_pool = false
  initial_node_count       = 2

  network         = google_compute_network.vpc.name
  subnetwork      = google_compute_subnetwork.subnet.name
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    # cluster_ipv4_cidr_block       = ""
    # cluster_secondary_range_name  = ""
    # services_ipv4_cidr_block      = ""
    # services_secondary_range_name = ""
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.69.0.16/28"
  }
}

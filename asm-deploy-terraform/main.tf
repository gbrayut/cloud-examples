# Example from https://github.com/GoogleCloudPlatform/anthos-service-mesh-samples/tree/main/docs/asm-gke-terraform

# This uses data sources instead of creating the clusters here since there are many different ways to create clusters
data "google_container_cluster" "iowa" {
  name               = "gke-iowa"
  location           = "us-central1"
  provider           = google-beta
}
data "google_container_cluster" "oregon" {
  name               = "gke-oregon"
  location           = "us-west1"
  provider           = google-beta
}
data "google_project" "project" {
  project_id = var.project_id
}

# Enable mesh API
resource "google_project_service" "meshapi" {
  project = var.project_id
  service = "mesh.googleapis.com"

  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_service#disable_dependent_services
  disable_dependent_services = true
}

# Enable mesh on fleet https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/gke_hub_feature
resource "google_gke_hub_feature" "fleetmesh" {
  name     = "servicemesh"
  location = "global"

  provider = google-beta
  depends_on = [
    google_project_service.meshapi
  ]
}

# Register GKE clusters with fleet
resource "google_gke_hub_membership" "iowa" {
  membership_id = "gke-iowa"
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${data.google_container_cluster.iowa.id}"
    }
  }
  provider = google-beta
}
resource "google_gke_hub_membership" "oregon" {
  membership_id = "gke-oregon"
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${data.google_container_cluster.oregon.id}"
    }
  }
  provider = google-beta
}

# Enable ASM Managed Control Plane and Data Plane on GKE clusters using Fleet API
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/gke_hub_feature_membership#example-usage---service-mesh
resource "google_gke_hub_feature_membership" "iowa" {
  location   = "global"
  feature    = "servicemesh"  # or google_gke_hub_feature.mesh.name
  membership = google_gke_hub_membership.iowa.membership_id
  mesh {
    # https://cloud.google.com/service-mesh/docs/managed/provision-managed-anthos-service-mesh#enable_automatic_management
    management = "MANAGEMENT_AUTOMATIC"
  }
  provider = google-beta
}
resource "google_gke_hub_feature_membership" "oregon" {
  location   = "global"
  feature    = "servicemesh"
  membership = google_gke_hub_membership.oregon.membership_id
  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
  provider = google-beta
}

# Then check status using: gcloud container fleet mesh describe

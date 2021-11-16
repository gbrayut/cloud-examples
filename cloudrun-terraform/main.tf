provider "google" {
  project     = "gregbray-12345"
  region      = "us-central1"
  zone        = "us-central1-c"
}

# Enable Cloud Run API in this project
resource "google_project_service" "run" {
  service = "run.googleapis.com"
}

# Create service account to run service
resource "google_service_account" "mycloudrun" {
  account_id   = "my-cloud-run"
  display_name = "Cloud Run Service Account"
}

# Give the service account access to whatever resources the service will need (Cloud SQL for example
resource "google_project_iam_member" "project" {
  role   = "roles/cloudsql.client"
  member = "serviceAccount:${google_service_account.mycloudrun.email}"
  project = google_cloud_run_service.myservice.project
}

# Policy to allow public access to Cloud Run endpoint
data "google_iam_policy" "noauth" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }
}

# Bind public policy to our Cloud Run service
resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.myservice.location
  project     = google_cloud_run_service.myservice.project
  service     = google_cloud_run_service.myservice.name
  policy_data = data.google_iam_policy.noauth.policy_data
}

# Example Cloud Run service (from https://www.sethvargo.com/configuring-cloud-run-with-terraform/)
resource "google_cloud_run_service" "myservice" {
  name     = "my-service"
  location = "us-central1"
  template {
    spec {
      # Use named Service Account instead of project default
      service_account_name = google_service_account.mycloudrun.email
      containers {
        image = "gcr.io/cloudrun/hello"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  # This resource won't work until the service is enabled
  depends_on = [google_project_service.run]
}

output "url" {
  value = google_cloud_run_service.myservice.status[0].url
}

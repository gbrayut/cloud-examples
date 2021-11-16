# Example from https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#example-usage---cloud-run-service-secret-volumes

# Enable Secrets API in this project
resource "google_project_service" "secrets" {
  service = "secretmanager.googleapis.com"
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret
resource "google_secret_manager_secret" "secret" {
  secret_id = "secret"
  replication {
    automatic = true
  }

  depends_on = [google_project_service.run]
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version
resource "google_secret_manager_secret_version" "secret-version-data" {
  secret = google_secret_manager_secret.secret.name
  secret_data = "secret-data"
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam
resource "google_secret_manager_secret_iam_member" "secret-access" {
  secret_id = google_secret_manager_secret.secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mycloudrun.email}"
  depends_on = [google_secret_manager_secret.secret]
}

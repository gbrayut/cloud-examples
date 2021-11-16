provider "google" {
  project = "gregbray-12345"
  region  = "us-central1"
  zone    = "us-central1-c"
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
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.mycloudrun.email}"
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

# Example Cloud Run service that uses secrets via env vars or mounted volume
resource "google_cloud_run_service" "myservice" {
  name     = "my-service"
  location = "us-central1"
  template {
    spec {
      # Use named Service Account instead of project default
      service_account_name = google_service_account.mycloudrun.email
      containers {
        # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#nested_containers
        # The echoserver is a public image that has most of what we need for testing
        image = "gcr.io/kubernetes-e2e-test-images/echoserver:2.1"
        # Change the container entrypoint so we can add some commands before calling the run.sh default entrypoint again
        command = ["/bin/sh"]
        # Inject env and secrets into the nginx lua template from https://github.com/kubernetes/kubernetes/blob/master/test/images/echoserver/nginx.conf
        # sed command adds to the end of the template using N (Buffer next line), a (append text to buffer), and r (Read file into buffer) commands
        # with \\n instead of \n because of terraform escape sequences causing issues
        args = ["-c", "env > /tmp/out;ls -ld /secrets/* >> /tmp/out; sed -i $'/^Request Body:/{N;a \\n;a env and Secrets:\\n; r /tmp/out\\n; r /secrets/not-a-real-secret\\n}' /etc/nginx/nginx.conf && /usr/local/bin/run.sh"]

        # Or remove the above image/command/args lines a deploy your own container like this one (see ./cloudrun-hello-go)
        #image = "us-central1-docker.pkg.dev/gregbray-12345/cloud-run-source-deploy/cloudrun-hello-go"

        # Accessing Secrets Option 1: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#example-usage---cloud-run-service-secret-environment-variables
        env {
          name = "SECRET_ENV_VAR_FAKE"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.secret.secret_id # Caution: This value will be printed in plain text if using above echoserver or cloudrun-hello-go
              key  = "1"
            }
          }
        }

        # Setup mount point in container for option 2 below
        volume_mounts {
          name       = "a-volume"
          mount_path = "/secrets"
        }
      }      
      # Accessing Secrets Option 2: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#example-usage---cloud-run-service-secret-volumes
      volumes {
        name = "a-volume"
        secret {
          secret_name = google_secret_manager_secret.secret.secret_id
          items {
            key  = "1"
            path = "not-a-real-secret"
          }
        }
      }

      # Accessing Secrets Option 3: direct access from code via Cloud APIs https://cloud.google.com/secret-manager/docs/reference/libraries
      # Slightly more secure since it prevents some attack vectors, but for the vast majority of case any of the above should be fine
      # More details at https://cloud.google.com/secret-manager/docs/best-practices#coding_practices
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
  autogenerate_revision_name = true

  # This resource won't work until the service is enabled
  depends_on = [google_project_service.run, google_secret_manager_secret_version.secret-version-data]
}

output "url" {
  value = google_cloud_run_service.myservice.status[0].url
}

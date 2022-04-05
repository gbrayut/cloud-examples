# Setup GAE project+application+service
resource "google_project" "my_gae_project" {
  name       = "gregbray-2022apr-test-gae"
  project_id = "gregbray-2022apr-test-gae"
  org_id     = var.my_org_id
  billing_account = var.my_billing_account
  skip_delete = true
}

resource "google_app_engine_application" "app" {
  project     = google_project.my_gae_project.project_id
  location_id = "us-central"
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/app_engine_standard_app_version
#resource "google_app_engine_standard_app_version" "default" {
#  project    = google_project.my_gae_project.project_id
#  version_id = "v1"
#  service    = "default"
#  runtime    = "go115" # https://cloud.google.com/appengine/docs/standard/runtimes
#
#  entrypoint {
#    shell = "go run ."
#  }
#
#  deployment {
#    zip {
#      # https://cloud.google.com/appengine/docs/standard/go111/create-app#download_the_hello_world_app
#      source_url = var.my_source_zip
#    }
#  }
#
#  env_variables = {
#    port = "8080"
#  }
#
#  depends_on = [
#    google_project.my_gae_project,
#  ]
#
#  delete_service_on_destroy = true
#}

# Verify working at https://gregbray-2022apr-test-gae.uc.r.appspot.com
// https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project.html
resource "google_folder" "development" {
  display_name = "Development"
  parent       = "organizations/10123456789"
}
resource "google_project" "my_project" {
  name       = "My Project"
  project_id = "your-project-id"
  folder_id  = google_folder.development.name   # specify folder location
  //org_id     = "10123456789"                  # or just specify org
}

// Folder level IAM https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_folder_iam
// NOTE: This is authoritative and would replace any other entries
resource "google_folder_iam_policy" "folder" {
  folder      = google_folder.development.name
  policy_data = data.google_iam_policy.owners.policy_data
}

// https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/iam_policy
data "google_iam_policy" "owners" {
  binding {
    role = "roles/owner"

    members = [
      "user:jane@example.com",
      "group:cloud-admins@example.com"
    ]
  }
}

// Can also set at project level using https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_iam
// This example uses non-authoratative iam_member entries which combine with other member resources

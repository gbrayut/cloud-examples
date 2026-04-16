variable "project_id" {
  type        = string
  description = "The Google Cloud Project ID"
  default     = "gregbray-testing"
}

variable "region" {
  type        = string
  description = "The Google Cloud Region"
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  default     = "testing-iowa"
}
variable "k8sresource_gateway" {
  type        = string
  description = "The k8sResource value to filter by"
  default     = "/namespaces/test-gclb/gateways/whereami-rilb"
}
variable "target_port" {
  type        = string
  description = "The target port used to filter forwarding rules"
  default     = "80"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_forwarding_rules
# unfiltered output similar to: gcloud compute forwarding-rules list --format=yaml --regions us-central1 --project my-project
data "google_compute_forwarding_rules" "my_gateway" {
  project = var.project_id
  region  = var.region
}

locals {
  # filters the above list of all to just the matching cluster + region/namespace + port_range 
  gtw_fr_self_link = one([
    for rule in data.google_compute_forwarding_rules.my_gateway.rules :
    rule.self_link if (
      try(jsondecode(rule.description)["k8sResource"], "") == var.k8sresource_gateway
      && endswith(try(jsondecode(rule.description)["k8sCluster"], ""), "locations/${var.region}/clusters/${var.cluster_name}")
      && rule.port_range == "${var.target_port}-${var.target_port}"
    )
  ])
}

output "gateway_forwarding_rule_self_link" {
  description = "The name of the forwarding rule matching the specified cluster and gateway"
  value = local.gtw_fr_self_link
  # switch to this for unfiltered list of rules displayed in terraform plan/apply
  #value = data.google_compute_forwarding_rules.my_gateway.rules
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_service_attachment
# or API examples at https://docs.cloud.google.com/vpc/docs/configure-private-service-connect-producer#expandable-2
resource "google_compute_service_attachment" "psc_ilb_service_attachment" {
  count = local.gtw_fr_self_link != null ? 1 : 0

  name        = "my-psc-service"
  region      = var.region
  description = "PSC attachment for port ${var.target_port} on gateway ${var.k8sresource_gateway} in cluster ${var.cluster_name}"

  target_service           = local.gtw_fr_self_link
  #domain_names             = ["gcp.example.com."]
  connection_preference    = "ACCEPT_AUTOMATIC"
  enable_proxy_protocol    = false  # only supported on L4 PSC https://docs.cloud.google.com/vpc/docs/about-vpc-hosted-services#proxy-protocol
  nat_subnets              = [google_compute_subnetwork.psc_nat_subnet.id]  
}

# PSC requires a NAT subnet in the producer vpc https://cloud.google.com/kubernetes-engine/docs/how-to/private-service-connect#producer_nat_subnet
data "google_compute_network" "producer_vpc" {
  name = "gke-vpc"
}
resource "google_compute_subnetwork" "psc_nat_subnet" {
  name          = "psc-nat-subnet"
  ip_cidr_range = "192.168.201.0/24"  # see https://docs.cloud.google.com/vpc/docs/about-vpc-hosted-services#nat-subnet-monitoring
  region        = var.region
  network       = data.google_compute_network.producer_vpc.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

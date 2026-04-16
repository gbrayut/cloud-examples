# Terraform for GKE Gateway L7 PSC Service Attachment

When [publishing services](https://docs.cloud.google.com/vpc/docs/about-vpc-hosted-services) using PSC, you usually use a Service type LoadBalancer (Network LB) and [ServiceAttachment](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net) as describe in the L4 PSC [code lab](https://codelabs.developers.google.com/cloudnet-psc-ilb-gke). However if the workload is exposed using a GKE Gateway (Application Load Balancer) you would have to manually create the [service attachment](https://docs.cloud.google.com/vpc/docs/configure-private-service-connect-producer) resources for L7 PSC. If you want to use Terraform, finding the name of the automatically generated Forwarding Rules can be difficult, but this example will show one way that should work.

## Steps

The [gke-manifest.yaml](./gke-manifest.yaml) example shows a target GKE Gateway using Regional Internal Load Balancer (gke-l7-rilb). Then the [main.tf](./main.tf) file uses the [google_compute_forwarding_rules](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_forwarding_rules) datasource to get a list of Forwarding Rules and filter via Cluster Name + Namespace/Gateway Name + port to find the matching rule for a programmed GKE Gateway.

```shell
$ cd tf-gke-psc

$ terraform init
Initializing the backend...
Initializing provider plugins...
- Reusing previous version of hashicorp/google from the dependency lock file
- Using previously-installed hashicorp/google v7.28.0
Terraform has made some changes to the provider dependency selections recorded
in the .terraform.lock.hcl file. Review those changes and commit them to your
version control system if they represent changes you intended to make.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

$ terraform apply
data.google_compute_network.producer_vpc: Reading...
data.google_compute_forwarding_rules.my_gateway: Reading...
data.google_compute_network.producer_vpc: Read complete after 0s [id=projects/gregbray-testing/global/networks/gke-vpc]
data.google_compute_forwarding_rules.my_gateway: Read complete after 0s [id=projects/gregbray-testing/regions/us-central1/forwardingRules]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # google_compute_service_attachment.psc_ilb_service_attachment[0] will be created
  + resource "google_compute_service_attachment" "psc_ilb_service_attachment" {
      + connected_endpoints                      = (known after apply)
      + connection_preference                    = "ACCEPT_AUTOMATIC"
      + description                              = "PSC attachment for port 80 on gateway /namespaces/test-gclb/gateways/whereami-rilb in cluster testing-iowa"
      + enable_proxy_protocol                    = false
      + fingerprint                              = (known after apply)
      + id                                       = (known after apply)
      + name                                     = "my-psc-service"
      + nat_subnets                              = (known after apply)
      + project                                  = "gregbray-testing"
      + propagated_connection_limit              = (known after apply)
      + psc_service_attachment_id                = (known after apply)
      + reconcile_connections                    = (known after apply)
      + region                                   = "us-central1"
      + self_link                                = (known after apply)
      + send_propagated_connection_limit_if_zero = false
      + target_service                           = "https://www.googleapis.com/compute/v1/projects/gregbray-testing/regions/us-central1/forwardingRules/gkegw1-407t-test-gclb-whereami-rilb-od85nwj1epts"
    }

  # google_compute_subnetwork.psc_nat_subnet will be created
  + resource "google_compute_subnetwork" "psc_nat_subnet" {
      + allow_subnet_cidr_routes_overlap = (known after apply)
      + creation_timestamp               = (known after apply)
      + external_ipv6_prefix             = (known after apply)
      + fingerprint                      = (known after apply)
      + gateway_address                  = (known after apply)
      + id                               = (known after apply)
      + internal_ipv6_prefix             = (known after apply)
      + ip_cidr_range                    = "192.168.201.0/24"
      + ipv6_cidr_range                  = (known after apply)
      + ipv6_gce_endpoint                = (known after apply)
      + name                             = "psc-nat-subnet"
      + network                          = "projects/gregbray-testing/global/networks/gke-vpc"
      + private_ip_google_access         = (known after apply)
      + private_ipv6_google_access       = (known after apply)
      + project                          = "gregbray-testing"
      + purpose                          = "PRIVATE_SERVICE_CONNECT"
      + region                           = "us-central1"
      + self_link                        = (known after apply)
      + stack_type                       = (known after apply)
      + state                            = (known after apply)
      + subnetwork_id                    = (known after apply)

      + secondary_ip_range (known after apply)
    }

Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + gateway_forwarding_rule_self_link = "https://www.googleapis.com/compute/v1/projects/gregbray-testing/regions/us-central1/forwardingRules/gkegw1-407t-test-gclb-whereami-rilb-od85nwj1epts"

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

google_compute_subnetwork.psc_nat_subnet: Creating...
google_compute_subnetwork.psc_nat_subnet: Still creating... [00m10s elapsed]
google_compute_subnetwork.psc_nat_subnet: Creation complete after 11s [id=projects/gregbray-testing/regions/us-central1/subnetworks/psc-nat-subnet]
google_compute_service_attachment.psc_ilb_service_attachment[0]: Creating...
google_compute_service_attachment.psc_ilb_service_attachment[0]: Still creating... [00m10s elapsed]
google_compute_service_attachment.psc_ilb_service_attachment[0]: Still creating... [00m20s elapsed]
google_compute_service_attachment.psc_ilb_service_attachment[0]: Creation complete after 22s [id=projects/gregbray-testing/regions/us-central1/serviceAttachments/my-psc-service]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

gateway_forwarding_rule_self_link = "https://www.googleapis.com/compute/v1/projects/gregbray-testing/regions/us-central1/forwardingRules/gkegw1-407t-test-gclb-whereami-rilb-od85nwj1epts"

```


## Future
* TODO: use google_compute_address.my_gateway_IP "IN_USE" status as a dependency or in a wait script?
* TODO: another example using [Config Connector](https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/compute/computeserviceattachment) CRDs?
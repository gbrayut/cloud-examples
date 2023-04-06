# Anthos Service Mesh terraform example

ASM has a few [deployment options](https://cloud.google.com/service-mesh/docs/overview#deployment_options):

* [in-cluster](https://cloud.google.com/service-mesh/docs/supported-features) via asmcli for GKE Standard and Anthos Multi/Hybrid Cloud deployments
* [managed](https://cloud.google.com/service-mesh/docs/managed/supported-features-mcp) via Fleet API for GKE Standard or Autopilot
* [managed via asmcli](https://cloud.google.com/service-mesh/docs/managed/provision-managed-anthos-service-mesh-asmcli) is also supported, but using Fleet API is recommended for GKE

Google also recommends using Managed Control Plane (MCP) and Data Plane (MDP) when possible since Google will handle the reliability, upgrades, scaling, and security of the service mesh for you.

## Provision managed Anthos Service Mesh

The [managed ASM instructions](https://cloud.google.com/service-mesh/docs/managed/provision-managed-anthos-service-mesh) show the steps required, however you can also use Terraform resources or modules if desired (currently via beta GCP provider). The [simple zonal example](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v25.0.0/examples/simple_zonal_with_asm) shows how to use an [asm terraform module](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v25.0.0/modules/asm) that makes changes to the ASM CRDs (like ControlPlaneRevision) and ConfigMaps (asm-options). But depending on your requirements those GKE and ASM modules may still need to be forked and customized to fit your needs.

The [main.tf example](./main.tf) in this directory will instead directly use the Terraform resources for GKE Fleet (previously know as GKE Hub) to configure ASM with MCP and MDP, which is the simplest method of getting started with managed ASM for GKE. If you still end up needing to make changes to ASM CRDs or ConfigMaps, you can use [Terraform resources](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/blob/e9a72cff0a8e7d35aaf84a7ca9d6788d02a864d4/modules/asm/main.tf#L44-L71) like the above modules do or apply those changes via Anthos Config Management or another Kubernetes CI/CD process.

Example of `terraform plan` output for enabling ASM on pre-existing gke-iowa and gke-oregon clusters:

```shell
$ terraform plan
data.google_container_cluster.oregon: Reading...
data.google_container_cluster.iowa: Reading...
data.google_project.project: Reading...
data.google_project.project: Read complete after 1s [id=projects/my-fleet-project]
data.google_container_cluster.oregon: Read complete after 1s [id=projects/my-fleet-project/locations/us-west1/clusters/gke-oregon]
data.google_container_cluster.iowa: Read complete after 2s [id=projects/my-fleet-project/locations/us-central1/clusters/gke-iowa]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following
symbols:
  + create

Terraform will perform the following actions:

  # google_gke_hub_feature.fleetmesh will be created
  + resource "google_gke_hub_feature" "fleetmesh" {
      + create_time    = (known after apply)
      + delete_time    = (known after apply)
      + id             = (known after apply)
      + location       = "global"
      + name           = "servicemesh"
      + project        = (known after apply)
      + resource_state = (known after apply)
      + state          = (known after apply)
      + update_time    = (known after apply)
    }

  # google_gke_hub_feature_membership.iowa will be created
  + resource "google_gke_hub_feature_membership" "iowa" {
      + feature    = "servicemesh"
      + id         = (known after apply)
      + location   = "global"
      + membership = "gke-iowa"
      + project    = (known after apply)

      + mesh {
          + management = "MANAGEMENT_AUTOMATIC"
        }
    }

  # google_gke_hub_feature_membership.oregon will be created
  + resource "google_gke_hub_feature_membership" "oregon" {
      + feature    = "servicemesh"
      + id         = (known after apply)
      + location   = "global"
      + membership = "gke-oregon"
      + project    = (known after apply)

      + mesh {
          + management = "MANAGEMENT_AUTOMATIC"
        }
    }

  # google_gke_hub_membership.iowa will be created
  + resource "google_gke_hub_membership" "iowa" {
      + id            = (known after apply)
      + membership_id = "gke-iowa"
      + name          = (known after apply)
      + project       = (known after apply)

      + endpoint {
          + gke_cluster {
              + resource_link = "//container.googleapis.com/projects/my-fleet-project/locations/us-central1/clusters/gke-iowa"
            }
        }
    }

  # google_gke_hub_membership.oregon will be created
  + resource "google_gke_hub_membership" "oregon" {
      + id            = (known after apply)
      + membership_id = "gke-oregon"
      + name          = (known after apply)
      + project       = (known after apply)

      + endpoint {
          + gke_cluster {
              + resource_link = "//container.googleapis.com/projects/my-fleet-project/locations/us-west1/clusters/gke-oregon"
            }
        }
    }

  # google_project_service.meshapi will be created
  + resource "google_project_service" "meshapi" {
      + disable_dependent_services = true
      + disable_on_destroy         = true
      + id                         = (known after apply)
      + project                    = "my-fleet-project"
      + service                    = "mesh.googleapis.com"
    }

Plan: 6 to add, 0 to change, 0 to destroy.
```

And you can then [verify the ASM deployment](https://cloud.google.com/service-mesh/docs/managed/provision-managed-anthos-service-mesh#verify_the_control_plane_has_been_provisioned) using:

```yaml
# gcloud container fleet mesh describe --project my-fleet-project
createTime: '2022-10-23T21:55:40.038433227Z'
membershipSpecs:
  projects/500123456789/locations/global/memberships/gke-iowa:
    mesh:
      management: MANAGEMENT_AUTOMATIC
  projects/500123456789/locations/global/memberships/gke-oregon:
    mesh:
      management: MANAGEMENT_AUTOMATIC
membershipStates:
  projects/500123456789/locations/global/memberships/gke-iowa:
    servicemesh:
      controlPlaneManagement:
        details:
        - code: REVISION_READY
          details: 'Ready: asm-managed'
        state: ACTIVE
      dataPlaneManagement:
        details:
        - code: OK
          details: Service is running.
        state: ACTIVE
    state:
      code: OK
      description: 'Revision(s) ready for use: asm-managed.'
      updateTime: '2023-04-06T17:20:56.022368494Z'
  projects/500123456789/locations/global/memberships/gke-oregon:
    servicemesh:
      controlPlaneManagement:
        details:
        - code: REVISION_READY
          details: 'Ready: asm-managed'
        state: ACTIVE
      dataPlaneManagement:
        details:
        - code: OK
          details: Service is running.
        state: ACTIVE
    state:
      code: OK
      description: 'Revision(s) ready for use: asm-managed.'
      updateTime: '2023-04-06T17:20:58.263993231Z'
name: projects/my-fleet-project/locations/global/features/servicemesh
resourceState:
  state: ACTIVE
spec: {}
state:
  state: {}
updateTime: '2023-04-06T17:21:05.784772586Z'
```

## Provisioning Istio Ingress and Egress Gateways

To provision Istio Gateways see [Installing and upgrading gateways](https://cloud.google.com/service-mesh/docs/gateways) and [asm-ingressgateway-classic example](../asm-ingressgateway-classic/).

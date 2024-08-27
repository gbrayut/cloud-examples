# Network Load Balancer Overview

TODO: describe Internal vs External, Global Access, [Proxy](https://cloud.google.com/load-balancing/docs/tcp/internal-proxy) vs [Passthrough](https://cloud.google.com/load-balancing/docs/internal), subsetting, ...

Good overview of the difference between [GCE_VM_IP and GCE_VM_IP_PORT](https://cloud.google.com/load-balancing/docs/negs/zonal-neg-concepts) Network Endpoint Groups and where each type can be used.

Even when using VPC Native GKE clusters, NLB are currently always routed thru node IP using iptables for NAT. So unlike ALB there is no native direct-to-pod option for NLB.

[Pricing](https://cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer#pricing_and_quotas) for Passthrough and Proxy Network Load balancer should be the same (based on number of forwarding rules and overall bandwidth). There is a proxy instance charge for L7 Application Load Balancers, but there is no equivalent per instance SKU for L4 NLBs. And because Global Access allows clients from any region to access your internal load balancer, additional cross-region data transfer charges are incurred when traffic is sent to or from a client in a different region than the load balancer.

See [base-whereami-spread.yaml](./base-whereami-spread.yaml) for example of NLB and Standalone NEG with more details in Google Cloud Console [Network Services](https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers) section.

## Internal Passthrough NLB

By default [Internal passthrough NLB](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing) use instance groups backends unless you enable endpoint subsetting on the cluster using `--enable-l4-ilb-subsetting`.

Subsetting will then create and use one `GCE_VM_IP` NEG per zone for Service type LoadBalancer (L4 NLB) instead of backend instance groups.

```
Default NLB unmanaged instance group backend format: k8s-ig--RANDOM_HASH
Default NLB forwarding rule: 32 hexadecimal digit GUID?
Examples:
  k8s-ig--9be17460365bd3d3
  a6026cb9fecd24fbabbe8b5b90722380

Subsetting NLB GCE_VM_IP NEG format: k8s2-CLUSTER_UID-NAMESPACE-SERVICE-RANDOM_HASH?
Subsetting NLB forwarding rule: k8s2-PROTOCOL-CLUSTER_UID-NAMESPACE-SERVICE-RANDOM_HASH?
Examples:
  k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
  k8s2-tcp-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
```

### Default Passthrough NLB Details

```shell
# Show pod replicaset, ip, zone, and assigned node
$ kubectl get endpointslices -n test-gclb -o jsonpath='{range .items[*]}{.metadata.name}{":\n"}{range .endpoints[*]}{"  "}{.targetRef.name}{" "}{.addresses[0]}{" "}{.zone}{" "}{.nodeName}{"\n"}{end}{end}'
whereami-spread-q6whh:
  whereami-spread-5f4578479f-hm4fm 10.248.1.19 us-central1-a gke-gke-iowa-default-pool-138fb5f3-x6jk
  whereami-spread-5f4578479f-9p6ql 10.248.0.10 us-central1-f gke-gke-iowa-default-pool-77f02a22-5gl3
  whereami-spread-5f4578479f-fpjcw 10.248.2.10 us-central1-c gke-gke-iowa-default-pool-703feb01-ch7l

# Show NLB (default, subsetting, and custom internal forwarding rules)
$ gcloud compute forwarding-rules list --filter="loadBalancingScheme=INTERNAL" --project gregbray-gke-v1
NAME                              REGION       IP_ADDRESS    IP_PROTOCOL  TARGET
a6026cb9fecd24fbabbe8b5b90722380  us-central1  10.31.232.10  TCP          us-central1/backendServices/a6026cb9fecd24fbabbe8b5b90722380

# Show instance group backends for default NLB
$ gcloud compute --project gregbray-gke-v1 instance-groups list --filter="name ~ ^k8s-ig-" 
NAME                      LOCATION       SCOPE  NETWORK  MANAGED  INSTANCES
k8s-ig--9be17460365bd3d3  us-central1-a  zone   gke-vpc  No       1
k8s-ig--9be17460365bd3d3  us-central1-c  zone   gke-vpc  No       1
k8s-ig--9be17460365bd3d3  us-central1-f  zone   gke-vpc  No       1

$ gcloud compute backend-services describe --project gregbray-gke-v1 a6026cb9fecd24fbabbe8b5b90722380
backends:
- balancingMode: CONNECTION
  group: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-f/instanceGroups/k8s-ig--9be17460365bd3d3
- balancingMode: CONNECTION
  group: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a/instanceGroups/k8s-ig--9be17460365bd3d3
- balancingMode: CONNECTION
  group: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-c/instanceGroups/k8s-ig--9be17460365bd3d3
connectionDraining:
  drainingTimeoutSec: 0
creationTimestamp: '2024-08-21T19:20:54.781-07:00'
description: '{"kubernetes.io/service-name":"test-gclb/whereami-spread"}'
fingerprint: Tni9Zu6xJds=
healthChecks:
- https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/global/healthChecks/k8s-9be17460365bd3d3-node
id: '7928243700019961449'
kind: compute#backendService
loadBalancingScheme: INTERNAL
name: a6026cb9fecd24fbabbe8b5b90722380
protocol: TCP
region: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/regions/us-central1
selfLink: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/regions/us-central1/backendServices/a6026cb9fecd24fbabbe8b5b90722380
sessionAffinity: NONE
timeoutSec: 30
```
### Subsetting Passthrough NLB Details

```shell
# Enable nlb subsetting on cluster and recreate NLB. See neg details at https://cloud.google.com/load-balancing/docs/negs/zonal-neg-concepts#subsetting
$ gcloud container clusters update gke-iowa --enable-l4-ilb-subsetting --project gregbray-gke-v1 --region us-central1
# Enabling L4 ILB Subsetting is a one-way operation.
# Once enabled, this configuration cannot be disabled.
# Existing ILB services should be recreated to start using Subsetting.

$ gcloud compute forwarding-rules list --filter="loadBalancingScheme=INTERNAL" --project gregbray-gke-v1
NAME                                                      REGION       IP_ADDRESS    IP_PROTOCOL  TARGET
k8s2-tcp-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9  us-central1  10.31.232.11  TCP          us-central1/backendServices/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9

$ gcloud compute backend-services describe --project gregbray-gke-v1 k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
backends:
- balancingMode: CONNECTION
  group: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
- balancingMode: CONNECTION
  group: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-c/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
- balancingMode: CONNECTION
  group: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-f/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
connectionDraining:
  drainingTimeoutSec: 30
creationTimestamp: '2024-08-21T20:04:53.349-07:00'
description: '{"networking.gke.io/service-name":"test-gclb/whereami-spread-new","networking.gke.io/api-version":"ga"}'
fingerprint: uokWy7wzymg=
healthChecks:
- https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/global/healthChecks/k8s2-j71w3amp-l4-shared-hc
id: '865872522433467450'
kind: compute#backendService
loadBalancingScheme: INTERNAL
name: k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
protocol: TCP
region: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/regions/us-central1
selfLink: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/regions/us-central1/backendServices/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
sessionAffinity: NONE
timeoutSec: 30

# View NEG for subsetting NLB
$ gcloud compute network-endpoint-groups --project gregbray-gke-v1 list
NAME                                                  LOCATION       ENDPOINT_TYPE  SIZE
k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9  us-central1-a  GCE_VM_IP      1
k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9  us-central1-c  GCE_VM_IP      1
k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9  us-central1-f  GCE_VM_IP      1

$ gcloud compute network-endpoint-groups --project gregbray-gke-v1 describe k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9 --zone us-central1-a
creationTimestamp: '2024-08-21T20:04:43.421-07:00'
description: '{"cluster-uid":"19a7a1cc-bd0d-4beb-b9ee-708f244715ad","namespace":"test-gclb","service-name":"whereami-spread-new","port":"0"}'
id: '293999074375046180'
kind: compute#networkEndpointGroup
name: k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
network: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/global/networks/gke-vpc
networkEndpointType: GCE_VM_IP
selfLink: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
size: 1
subnetwork: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/regions/us-central1/subnetworks/gke-iowa-subnet
zone: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a

# Similar results as Kubernetes Resource Model
$ kubectl get svcneg -n test-gclb k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9 -o yaml
apiVersion: networking.gke.io/v1beta1
kind: ServiceNetworkEndpointGroup
metadata:
  creationTimestamp: "2024-08-22T03:04:43Z"
  finalizers:
  - networking.gke.io/neg-finalizer
  generation: 8
  labels:
    networking.gke.io/managed-by: neg-controller
    networking.gke.io/service-name: whereami-spread-new
    networking.gke.io/service-port: "0"
  name: k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
  namespace: test-gclb
  ownerReferences:
  - apiVersion: v1
    blockOwnerDeletion: false
    controller: true
    kind: Service
    name: whereami-spread-new
    uid: 968ff266-a5d4-4126-846b-c7fd7e3fd83b
  resourceVersion: "4468054"
  uid: fb318467-294e-48d1-8593-9da2b8e3d4a1
spec: {}
status:
  conditions:
  - lastTransitionTime: "2024-08-22T03:05:00Z"
    message: ""
    reason: NegInitializationSuccessful
    status: "True"
    type: Initialized
  - lastTransitionTime: "2024-08-22T03:05:01Z"
    message: ""
    reason: NegSyncSuccessful
    status: "True"
    type: Synced
  lastSyncTime: "2024-08-26T19:24:32Z"
  networkEndpointGroups:
  - id: "293999074375046180"
    networkEndpointType: GCE_VM_IP
    selfLink: https://www.googleapis.com/compute/beta/projects/gregbray-gke-v1/zones/us-central1-a/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
  - id: "7347203498966717502"
    networkEndpointType: GCE_VM_IP
    selfLink: https://www.googleapis.com/compute/beta/projects/gregbray-gke-v1/zones/us-central1-c/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
  - id: "3178631124778423352"
    networkEndpointType: GCE_VM_IP
    selfLink: https://www.googleapis.com/compute/beta/projects/gregbray-gke-v1/zones/us-central1-f/networkEndpointGroups/k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9
```

## Standalone NEG

GKE [Standalone NEG](https://cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg) will create one zonal `GCE_VM_IP_PORT` per zone and lets you specify the NEG name via annotation on Service resource.

If name is omited it will use the format: `k8s1-CLUSTER_UID-NAMESPACE-SERVICE-PORT-RANDOM_HASH`

Also Size seems to always be zero when viewed via gcloud?

```shell
$ gcloud compute network-endpoint-groups describe --project gregbray-gke-v1 test-standalone --zone us-central1-a
creationTimestamp: '2024-08-21T22:37:51.982-07:00'
description: '{"cluster-uid":"19a7a1cc-bd0d-4beb-b9ee-708f244715ad","namespace":"test-gclb","service-name":"wai-sa-neg","port":"80"}'
id: '8613878307624808512'
kind: compute#networkEndpointGroup
name: test-standalone
network: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/global/networks/gke-vpc
networkEndpointType: GCE_VM_IP_PORT
selfLink: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a/networkEndpointGroups/test-standalone
size: 0
subnetwork: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/regions/us-central1/subnetworks/gke-iowa-subnet
zone: https://www.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a

$ kubectl get svcneg -n test-gclb test-standalone -o yaml
apiVersion: networking.gke.io/v1beta1
kind: ServiceNetworkEndpointGroup
metadata:
  creationTimestamp: "2024-08-22T05:37:51Z"
  finalizers:
  - networking.gke.io/neg-finalizer
  generation: 53
  labels:
    networking.gke.io/managed-by: neg-controller
    networking.gke.io/service-name: wai-sa-neg
    networking.gke.io/service-port: "80"
  name: test-standalone
  namespace: test-gclb
  ownerReferences:
  - apiVersion: v1
    blockOwnerDeletion: false
    controller: true
    kind: Service
    name: wai-sa-neg
    uid: 92370e9b-a1f1-4496-ad36-18adbd7034b3
  resourceVersion: "4493172"
  uid: 4cbb0bc3-d47f-47a0-96b6-f4738e422eab
spec: {}
status:
  conditions:
  - lastTransitionTime: "2024-08-22T05:38:10Z"
    message: ""
    reason: NegInitializationSuccessful
    status: "True"
    type: Initialized
  - lastTransitionTime: "2024-08-22T05:38:11Z"
    message: ""
    reason: NegSyncSuccessful
    status: "True"
    type: Synced
  lastSyncTime: "2024-08-26T20:03:04Z"
  networkEndpointGroups:
  - id: "8613878307624808512"
    networkEndpointType: GCE_VM_IP_PORT
    selfLink: https://www.googleapis.com/compute/beta/projects/gregbray-gke-v1/zones/us-central1-a/networkEndpointGroups/test-standalone
  - id: "4604501649336791128"
    networkEndpointType: GCE_VM_IP_PORT
    selfLink: https://www.googleapis.com/compute/beta/projects/gregbray-gke-v1/zones/us-central1-c/networkEndpointGroups/test-standalone
  - id: "8327605302688706642"
    networkEndpointType: GCE_VM_IP_PORT
    selfLink: https://www.googleapis.com/compute/beta/projects/gregbray-gke-v1/zones/us-central1-f/networkEndpointGroups/test-standalone
```

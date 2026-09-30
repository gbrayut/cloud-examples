# Global External Proxy NLB using GKE standalone NEGs

[Proxy Network Load Balancers](https://docs.cloud.google.com/load-balancing/docs/proxy-network-load-balancer) (NLBs) are Layer 4 reverse proxies that distribute TCP traffic across various backend types. While you can deploy [Passthrough NLBs](https://docs.cloud.google.com/load-balancing/docs/passthrough-network-load-balancer) in GKE using [Service](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer) resources of **type: LoadBalancer** or Layer 7 Application Load Balancers (ALBs) using the GKE Gateway Controller, GKE does not currently provide GatewayClasses for TCPRoute or Proxy NLBs. Instead, you must use [standalone NEGs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg), where GKE automatically manages zonal GCE_VM_IP_PORT Network Endpoint Groups (NEGs) targeting your workload's pods while you configure the remaining Proxy NLB resources manually or using Infrastructure as Code tooling. This guide demonstrates using gcloud commands to configure a global external Proxy NLB backed by standalone NEGs across two regional GKE clusters.

Please refer to the [Load balancing feature comparison](https://docs.cloud.google.com/load-balancing/docs/features) documentation for a detailed breakdown of capabilities across load balancer types.

## Deploy Workload and Annotate Service

First, deploy a workload to one or more clusters within the same project. The [base-whereami-spread.yaml](../base-whereami-spread.yaml) manifest uses [topologySpreadConstraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) with **minDomains: 3** to spread pods across each of the three zones where nodes are provisioned by a default regional cluster. The **whereami-spread** Service creates an internal Passthrough NLB (useful for testing) and the **wai-sa-neg** service applies the [standalone NEG annotation](https://github.com/gbrayut/cloud-examples/blob/main/gke-gclb-misc/base-whereami-spread.yaml#L115) with **"zones":["*"]** to pre-provision empty NEGs for non-serving zones (useful for regional workloads not using minDomains or explicit topology constraints).

```shell
# Apply workload to the first cluster
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/base-whereami-spread.yaml

# Then repeat for other clusters in the same region or other regions as needed
# But all clusters must exist in the same project or as part of the same shared VPC

# View Network Endpoint Groups
gcloud compute network-endpoint-groups list --filter "name:test-standalone"
NAME             LOCATION       ENDPOINT_TYPE   SIZE
test-standalone  us-central1-a  GCE_VM_IP_PORT  1
test-standalone  us-central1-b  GCE_VM_IP_PORT  1
test-standalone  us-central1-c  GCE_VM_IP_PORT  0 <--- no pods in this zone, cluster currently uses a/b/f
test-standalone  us-central1-f  GCE_VM_IP_PORT  1
test-standalone  us-west3-a     GCE_VM_IP_PORT  1
test-standalone  us-west3-b     GCE_VM_IP_PORT  1
test-standalone  us-west3-c     GCE_VM_IP_PORT  1

# View target IPs for a zonal NEG (should match the pod IPs seen using kubectl)
gcloud compute network-endpoint-groups list-network-endpoints test-standalone --zone us-central1-a
INSTANCE                                 IP_ADDRESS     IPV6_ADDRESS  PORT  FQDN  CLIENT_DESTINATION_PORT
gke-gke-iowa-default-pool-dfbb0f6a-2bnq  10.27.128.148                8080

# Decrease or increase the number of pods in the deployment to test topologySpreadConstraints
kubectl scale -n test-gclb deploy/whereami-spread --replicas=2
```

## Configure Proxy NLB Firewall Rules and Health Checks

You can create the remaining load balancer components using gcloud, Terraform, Config Connector, or your preferred Infrastructure as Code (IaC) tooling. The [GCLB architecture docs](https://docs.cloud.google.com/load-balancing/docs/tcp#components) detail the different components and how they link together. In this example we are using a Global External Proxy NLB distributing across GKE backends in us-central1 and us-west3 regions. The steps would be similar for Regional and/or Internal Proxy NLB, but regional proxies would require using **REGIONAL_MANAGED_PROXY** subnets.

```shell
# Configure globally managed proxy subnets for each region
# Similar to https://docs.cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-cross-reg-internal#gcloud_1
gcloud compute networks subnets create proxy-iowa-global \
  --purpose=GLOBAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=us-central1 \
  --network "projects/my-project/global/networks/gke-vpc" \
  --range=10.210.0.0/23
gcloud compute networks subnets create proxy-slc-global \
  --purpose=GLOBAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=us-west3 \
  --network "projects/my-project/global/networks/gke-vpc" \
  --range=10.210.2.0/23

# create firewall rules using existing Node network tags https://docs.cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#configure_firewall_rules
# gcloud container clusters describe gke-iowa --region us-central1 --format='value[separator=","](name,id)' | awk -F, '{ print "gke-" $1 "-" substr($2, 1, 8) "-node"}'
NODENETWORKTAG="gke-gke-iowa-79504dcc-node,gke-gke-slc-603df75c-node"
gcloud compute firewall-rules create fw-allow-health-checks \
  --network=gke-vpc --action=allow --direction=ingress \
  --description="Allow managed health check IP ranges to access any target port on nodes/pods" \
  --source-ranges="35.191.0.0/16,130.211.0.0/22,209.85.152.0/22,209.85.204.0/22" \
  --target-tags=$NODENETWORKTAG \
  --rules=tcp
# Proxy subnets (from above) will also need firewall rules to connect to workload target port on pods
gcloud compute firewall-rules create fw-allow-proxy-targets \
  --network=gke-vpc --action=allow --direction=ingress \
  --description="Allow Global Managed Proxy subnet ranges to access target port(s) on pods" \
  --source-ranges=10.210.0.0/22 --target-tags=$NODENETWORKTAG \
  --rules=tcp:8080

# Define http health check https://docs.cloud.google.com/sdk/gcloud/reference/compute/health-checks/create/http
gcloud compute health-checks create http global-whereami-http-hc \
   --global --check-interval="10s" --host "whereami.example.com" --use-serving-port
```

## Configure Proxy NLB Backend Service and Add NEGs

Next, create a Backend Service (BES) and attach each zonal standalone NEG. Because this Proxy NLB uses NEGs rather than instance groups, the backend service must use the [CONNECTION balancing mode](https://docs.cloud.google.com/load-balancing/docs/backend-service#connection_balancing_mode). This mode evaluates backend capacity based on simultaneous open TCP connections, configured either as a total ceiling per zone (**--max-connections**) or as a steady-state per-target max (**--max-connections-per-endpoint**).

While this guide sets the per-pod capacity to 100 connections as an example, you should tune this value to your workload's specific sizing and connection limits. Setting **--max-connections-per-endpoint=0** is also useful for draining a zone and preventing new connections from being routed to that NEG provided there are other healthy NEGs available in the backend service.

```shell
# Configure global external Backend Service using health check from above
gcloud compute backend-services create whereami-example-bes \
  --global --load-balancing-scheme EXTERNAL_MANAGED \
  --protocol=TCP --health-checks=global-whereami-http-hc \
  --global-health-checks

# Start by adding the standalone NEGs for two of the six zones
# https://docs.cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#add_backends
gcloud compute backend-services add-backend whereami-example-bes \
  --global --network-endpoint-group="test-standalone" \
  --network-endpoint-group-zone="us-central1-a" \
  --balancing-mode CONNECTION --max-connections-per-endpoint=100
gcloud compute backend-services add-backend whereami-example-bes \
  --global --network-endpoint-group="test-standalone" \
  --network-endpoint-group-zone="us-central1-b" \
  --balancing-mode CONNECTION --max-connections-per-endpoint=100

# With identical capacities, new connections should be roughly split evenly across the two zones
# Asymmetric limits (like 100 vs. 50) can help shape traffic distribution, but this is a very 
# coarse mechanism based on connection headroom, not true L7 ALB weighted round-robin

# You can update NEG balancing parameters in-place on the backend service if needed https://docs.cloud.google.com/sdk/gcloud/reference/compute/backend-services/update-backend#--max-connections-per-endpoint
# For example, to drain us-central1-a without dropping existing connections:
gcloud compute backend-services update-backend whereami-example-bes \
  --global --network-endpoint-group="test-standalone" \
  --network-endpoint-group-zone="us-central1-a" \
  --balancing-mode CONNECTION --max-connections-per-endpoint=0

# NOTE: Changes to these values may take 3-5 minutes to propagate
```

## Configure TCP Target Proxy and Forwarding Rule

After adding the NEGs for all six zones (three per cluster from the previous **network-endpoint-groups list** output), configure a TCP proxy using EXTERNAL_MANAGED scheme and a global external anycast IP address. Because this is a reverse proxy, the original client connection is terminated at the proxy and a separate TCP connection is established from the proxy to each backend. To pass the original connection metadata to your workload, you can optionally enable [PROXY Protocol v1](https://docs.cloud.google.com/load-balancing/docs/tcp/set-up-global-ext-proxy-tcp#proxy-protocol) using **--proxy-header=PROXY_V1**. When enabled, the proxy prepends an initial human-readable header string containing the client source IP, destination IP, and port numbers to the TCP payload at the beginning of each backend connection.

```shell
# Create global external Proxy LB https://docs.cloud.google.com/load-balancing/docs/tcp
# https://docs.cloud.google.com/sdk/gcloud/reference/compute/target-tcp-proxies/create
gcloud compute target-tcp-proxies create gxlb-whereami-example \
  --global --load-balancing-scheme EXTERNAL_MANAGED --proxy-header NONE \
  --description="Global External Proxy NLB using GKE Standalone NEGs" \
  --global-backend-service --backend-service="whereami-example-bes"

# Create external anycast based global listener
# https://docs.cloud.google.com/sdk/gcloud/reference/compute/forwarding-rules/create
gcloud compute forwarding-rules create whereami-example-fr \
  --global --load-balancing-scheme EXTERNAL_MANAGED \
  --ports 80 --target-tcp-proxy gxlb-whereami-example 

# View IP Address assignment (or use --address="my-global-ip" above for a reserved ip)
gcloud compute forwarding-rules list --filter "target:gxlb-whereami-example"
NAME                 REGION  IP_ADDRESS     IP_PROTOCOL  TARGET
whereami-example-fr          1.2.3.4        TCP          gxlb-whereami-example
```

## Troubleshooting and Testing Proxy NLB

You can monitor backend status and troubleshoot routing issues in the Google Cloud Console under [Network Services -> Load Balancing](https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers). If endpoints appear unhealthy, enable [health check logging](https://docs.cloud.google.com/load-balancing/docs/health-check-logging) to view detailed probe results, connection errors, and state transitions in Google Cloud Logging.

```shell
IP=1.2.3.4
# View connection details
curl -vs --resolve whereami.example.com:80:$IP http://whereami.example.com

# Just return zone from selected backend pod
curl -s --resolve whereami.example.com:80:$IP http://whereami.example.com/zone

# Simple loop test with 5 second timeout and displaying timestamps
for i in {1..999}; do curl -s --max-time 5 --resolve whereami.example.com:80:$IP http://whereami.example.com/zone;printf " at [%(%F %T)T]\n";sleep 1;done

# While running the above try adding or removing NEGs from the Backend Service
# Or use --max-connections-per-endpoint to adjust the connection limits
```

## Cleanup Steps
When finished testing you can use the following to delete the resources created above:

```shell
gcloud compute forwarding-rules delete whereami-example-fr --global --quiet
gcloud compute target-tcp-proxies delete gxlb-whereami-example --global --quiet
gcloud compute backend-services delete whereami-example-bes --global --quiet
gcloud compute health-checks delete global-whereami-http-hc --global --quiet

gcloud compute firewall-rules delete fw-allow-proxy-targets
gcloud compute firewall-rules delete fw-allow-health-checks

gcloud compute networks subnets delete proxy-slc-global --region=us-west3
gcloud compute networks subnets delete proxy-iowa-global --region=us-central1
```

## Alternative Approaches to Traffic Management

Standalone NEGs allow you to configure advanced Google Cloud Load Balancing features that are not natively exposed through the GKE Gateway controller. Depending on your traffic management and architecture requirements, you may also want to explore these alternatives:

- [Cloud DNS Routing Policies](https://docs.cloud.google.com/dns/docs/routing-policies-overview): If you need weighted distribution across multiple clusters, geographic steering, or cross-region failover without managing reverse-proxy infrastructure, DNS routing policies provide a flexible client-side alternative. They also resolve seamlessly across heterogeneous targets, including on-premises environments and multi-cloud endpoints.

- [Multi-Cluster Ingress](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/multi-cluster-ingress) (MCI) and Gateways (MCG): For HTTP/HTTPS workloads spanning multiple GKE clusters, MCI and MCG provide native, declarative multi-cluster load balancing.

- [Service Extensions](https://docs.cloud.google.com/service-extensions/docs/lb-extensions-overview): If you need custom L7 routing, in-line payload inspection, or fine-grained traffic manipulation beyond standard load balancer capabilities, Service Extensions allow you to inject custom WebAssembly (Wasm) plugins or gRPC callouts directly into the data path of supported Application Load Balancers.

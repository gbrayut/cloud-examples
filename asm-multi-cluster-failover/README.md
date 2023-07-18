# Anthos Service Mesh - Multi Cluster Failover

## Setup Multi-Cluster Mesh on GKE

Following the [GKE multi-cluster mesh](https://cloud.google.com/service-mesh/docs/unified-install/gke-install-multi-cluster#zonal) instruction:

1. Create two or more GKE clusters (see [example](../common/new-project-gke.sh)) with the following features (reference [gcloud container clusters create](https://cloud.google.com/sdk/gcloud/reference/container/clusters/create) for more details):
    * Private clusters across regions require [global access](https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters#cp-global-access) `--enable-master-global-access`
    * Also [authorized networks](https://cloud.google.com/kubernetes-engine/docs/how-to/authorized-networks) should allow cross-cluster access (control plane to control plane) for service discovery
    * All clusters should be registered to the same fleet `--fleet-project="abc"` 
    * Cluster should have Workload Identity `--workload-pool="abc.svc.id.goog"` and [service mesh](../asm-deploy-terraform) configured
    * [Gateway API](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways#enable-gateway) is also [recommended](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) but not required `--gateway-api="standard"`

1. Create firewall rule(s) to allow [pod-to-pod traffic](https://cloud.google.com/service-mesh/docs/unified-install/gke-install-multi-cluster#create_firewall_rule) across GKE clusters. Something like this using pod IP ranges and gke node tags:
    ```shell
    gcloud compute firewall-rules create istio-multicluster-pods \
    --allow=tcp,udp,icmp,esp,ah,sctp \
    --direction=INGRESS \
    --priority=900 \
    --source-ranges="10.104.0.0/13,10.96.0.0/13" \
    --target-tags="gke-gke-oregon-3f72abe3-node,gke-gke-slc-ae43c0f4-node" \
    --network=gke-vpc --quiet
    ```

1. Configure multi-cluster [endpoint discovery](https://cloud.google.com/service-mesh/docs/unified-install/gke-install-multi-cluster#configure_endpoint_discovery) for the service mesh:
    ```shell
    # Install ASM using fleet api (or use asmcli if advanced features are required)
    gcloud container fleet mesh update --management automatic --memberships gke-oregon --project abc
    gcloud container fleet mesh update --management automatic --memberships gke-slc --project abc
    # Wait for "code: REVISION_READY details: 'Ready: asm-managed'" on all clusters
    gcloud container fleet mesh describe

    # Then on all clusters enable endpoint discovery using asm-options configmap
    kubectl patch configmap/asm-options -n istio-system --type merge -p '{"data":{"multicluster_mode":"connected"}}'

    # Confirm secrets for remote clusters are now available on all clusters
    $ kubectl get secrets -n istio-system -l istio.io/owned-by=mesh.googleapis.com,istio/multiCluster=true
    NAME                                                                               TYPE     DATA   AGE
    istio-remote-secret-projects-503076227230-locations-us-west3-memberships-gke-slc   Opaque   1      15h
    ```

1. Optional: Update `istio-system/istio-asm-managed` (or equivalent) configmap to exclude any services that should [remain local to the cluster](https://istio.io/latest/docs/ops/configuration/traffic-management/multicluster/):
    ```shell
    kubectl edit cm -n istio-system istio-asm-managed
    # it should look something like this to configure services as local only
    apiVersion: v1
    data:
      mesh: |2-

        # This section can be updated with user configuration settings from https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/
        # Some options required for ASM to not be modified will be ignored
        serviceSettings:
        - hosts:
          - '*.istio-ingress.svc.cluster.local'     # All services in istio-ingress
          - 'foo.namespace.svc.cluster.local'       # Single sepecific service
          settings:
            clusterLocal: true
    
    # You can also limit which services get exported to namespaces using the exportTo field
    # Which can help reduce istio control plane traffic if you have a large number of services
    # See https://istio.io/latest/docs/ops/best-practices/traffic-management/#cross-namespace-configuration
    ```

## Deploy Istio Resources and Sample App
There are a [few different ways](../asm-ingressgateway-classic) to install istio-ingressgateway, but this example uses the `networking.istio.io` istio classic api resources and a GKE managed NLB (service type LoadBalancer):

```shell
# Run these commands on both clusters to create istio-ingress namespace and resources
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/base-ingressgateway.yaml

# Also create Internal NLB with global access so TLS can be terminated via ASM
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/svc-nlb-internal.yaml

# Then apply Istio resources for gateway, virtual service, and destination rule (See section below for more details)
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-multi-cluster-failover/gw-vs-dr.yaml

# And two copies of the whereami sample app into both clusters:
#   app-1 permissive mTLS with VS+DR using locality loadbalancing and primary/secondary subsets
#   app-2 strict mTLS with default mesh settings (no VS/DR) that can be used as an in-mesh test app
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-1-permissive.yaml
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-2-strict.yaml
```

## Configure private zone DNS record for Istio-IngressGateway NLBs

Use [Cloud DNS with routing policy](https://cloud.google.com/blog/products/networking/introducing-automated-failover-for-private-workloads-using-cloud-dns-routing-policies-with-health-checks) of either weighted, geo, or failover to manage request across the GKE clusters. In this case we will use [failover policy](https://cloud.google.com/dns/docs/policies-overview#failover-policy) to create an active/hot-standby for istio-ingressgateway.

```shell
gcloud dns --project=vpc-project record-sets create \
    whereami.example.com. --zone="example" --type="A" \
    --ttl="300" --routing-policy-type="FAILOVER" --enable-health-checking \
    --routing-policy-primary-data="projects/gke-project/regions/us-west1/forwardingRules/a321f0be283a140b596e0ec52008fae1" \
    --backup-data-trickle-ratio="0.0" --routing-policy-backup-data-type="GEO" \
    --routing-policy-backup-data="us-west1=projects/gke-project/regions/us-west3/forwardingRules/ac32a3df087494e7ca0f61c6685050ea"

# Can test that the failover works by scaling replica down to zero (after removing HPA).
# But it may take x minutes for the failover to work
kubectl scale deployment -n istio-ingress istio-ingressgateway --replicas=0
TODO: fix health check? default uses envoy 15021, and doesn't seem to fail with zero replicas...
```

## Validate Multi-Cluster Mesh Endpoint Discovery

With everything in place we can now validate the mesh is routing requests for services across both clusters. In the examples below we are designating the `gke-oregon` cluster (pod IPs: `10.96.x.x`, service IPs: `10.68.x.x`) as the primary and `gke-slc` cluster (pod IPs: `10.104.x.x`, service IPs: `10.67.x.x`) as the secondary.

```shell
# Add a test pod to istio-system namespace so we can do curl testing of NLBs without 
# an istio sidecar (better mimics request from a VM outside the mesh)
kubectl run test -n istio-system --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.19

# Optional: on both clusters scale deployments down to a single pod to make things easier to read
kubectl delete hpa -n istio-ingress istio-ingressgateway  # Cannot scale down manually if HPA exists
kubectl scale deployment -n istio-ingress istio-ingressgateway --replicas=1
kubectl scale -n app-1 deploy/whereami --replicas=1
kubectl scale -n app-2 deploy/whereami --replicas=1

# Check that all pods in both clusters are running as expected and the apps have sidecars injected (READY 2/2)
kubectl get pods -A -o wide
NAMESPACE       NAME                                  READY   STATUS    RESTARTS   AGE    IP             NODE
app-1           whereami-75d8bfc59-87p85              2/2     Running   0          127m   10.104.1.29    gke-gke-slc-default-pool-a651f919-7q3p
app-2           whereami-75d8bfc59-rmcfg              2/2     Running   0          127m   10.104.1.30    gke-gke-slc-default-pool-a651f919-7q3p
gke-mcs         gke-mcs-importer-798bb94dbd-tmf5g     1/1     Running   0          16h    10.104.1.8     gke-gke-slc-default-pool-a651f919-7q3p
istio-ingress   istio-ingressgateway-78d5d78c6-fbvz4  1/1     Running   0          3h     10.104.1.25    gke-gke-slc-default-pool-a651f919-7q3p
istio-system    test                                  1/1     Running   0          130m   10.104.1.28    gke-gke-slc-default-pool-a651f919-7q3p

# See local pod details using endpointslices
kubectl describe endpointslices.discovery.k8s.io -n app-1 whereami-zpftq
Name:         whereami-zpftq
Namespace:    app-1
Labels:       endpointslice.kubernetes.io/managed-by=endpointslice-controller.k8s.io
              kubernetes.io/service-name=whereami
Annotations:  endpoints.kubernetes.io/last-change-trigger-time: 2023-07-18T16:06:47Z
AddressType:  IPv4
Ports:
  Name  Port  Protocol
  ----  ----  --------
  http  8080  TCP
Endpoints:
  - Addresses:  10.96.2.27
    Conditions:
      Ready:    true
    Hostname:   <unset>
    TargetRef:  Pod/whereami-75d8bfc59-64cm9
    NodeName:   gke-gke-oregon-default-pool-1555d6b4-lh8k
    Zone:       us-west1-c
Events:         <none>

# Use istioctl to see multi-cluster endpoints, subsets and health status of the sidecar for a specific pod
istioctl --context=$GKECONTEXT pc endpoints whereami-75d8bfc59-64cm9.app-1 --port 8080
ENDPOINT             STATUS      OUTLIER CLUSTER
# these are the app-1 and app-2 endpoints from gke-slc
10.104.1.29:8080     HEALTHY     OK      outbound|80||whereami.app-1.svc.cluster.local
10.104.1.30:8080     HEALTHY     OK      outbound|80||whereami.app-2.svc.cluster.local
# these are the app-1 and app-2 endpoints from gke-oregon
10.96.2.27:8080      HEALTHY     OK      outbound|80||whereami.app-1.svc.cluster.local
10.96.2.28:8080      HEALTHY     OK      outbound|80||whereami.app-2.svc.cluster.local
# these are the app-1 subsets named primary and secondary
10.96.2.27:8080      HEALTHY     OK      outbound|80|primary|whereami.app-1.svc.cluster.local
10.104.1.29:8080     HEALTHY     OK      outbound|80|secondary|whereami.app-1.svc.cluster.local

# See the full proxy config for the ingress gateway
istioctl --context=$KC pc all istio-ingressgateway-78d5d78c6-m8b7h.istio-ingress
# Or the entire envoy config dump with EDS details
kubectl exec -n istio-ingress -it istio-ingressgateway-78d5d78c6-m8b7h -c istio-proxy -- curl -sS localhost:15000/config_dump?include_eds=true > /tmp/envoy_config_dump_with_eds.json
```

## Validate Multi-Cluster Mesh Failover

The [gw-vs-dr.yaml](./gw-vs-dr.yaml) example shows how you can configure multi-cluster routing using:
* [prefix matches](./gw-vs-dr.yaml#L28-L55) on the virtual service used by istio-ingress gateway. These will only work for requests from outside the cluster, but a similar virtual service could be created for `host: name.namespace.svc.cluster.local`
* [locality loadbalancing](https://istio.io/latest/docs/tasks/traffic-management/locality-load-balancing/failover/) with [failoverPriority](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LocalityLoadBalancerSetting) in the [destination rule](./gw-vs-dr.yaml#L77-L89)
* named [subsets](./gw-vs-dr.yaml#L94-L102) in the destination rule for explicit routing (note these do not support automatic failover). This uses a special [label](https://istio.io/latest/docs/reference/config/labels/) label to match the GKE clusterID like `topology.istio.io/cluster: cn-gregbray-vpc-us-west1-gke-oregon`
```shell
# Simulate a client outside the cluster but in the same region using the test pod from above
kubectl exec -it -n istio-system test -- /bin/bash

# Use Metadata server to see the container's project and zone
appuser@test:/app$ curl -sH "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/zone";echo '';
projects/50123456789/zones/us-west1-c

# the whereami container has endpoints like whatever/zone and something/cluster_name to show details about the pod
# see https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/tree/main/whereami

# when using .../app-1/zone with locality DR you should always see the local region (if there are healthy pods)
appuser@test:/app$ curl http://whereami.example.com/app-1/zone;echo ''
us-west1-c
us-west1-c
us-west1-c

# when using .../app-2/zone it will bounce between healthy pods in all regions
appuser@test:/app$ curl http://whereami.example.com/app-2/zone;echo ''
us-west3-c
us-west1-c
us-west3-c
us-west1-c

# when using .../zone or .../cluster_name it will use the locality loadbalancing of app-1 destination rule
appuser@test:/app$ curl http://whereami.example.com/cluster_name;echo ''
gke-oregon
gke-oregon
gke-oregon

# if you use the scale command to set replica=0 the app-1 routes will failover to the other cluster
kubectl scale -n app-1 deploy/whereami --replicas=0    # run this against the primary cluster (gke-oregon)
appuser@test:/app$ curl http://whereami.example.com/cluster_name;echo ''
gke-oregon
gke-oregon
...     # when pods become unhealthy it will failover
...     # but you may see an error if envoy already selected the unhealthy/terminating pod
upstream connect error or disconnect/reset before headers. reset reason: connection failure, transport failure reason: delayed connect error: 111
...
gke-slc
gke-slc
gke-slc
gke-slc

# when using .../primary/... or .../secondary/... it will only use pods from that subset
# if there are no healthy pods matching that label selector it will return "no healthy upstream"
appuser@test:/app$ curl http://whereami.example.com/primary/cluster_name;echo ''
gke-oregon
gke-oregon
no healthy upstream
no healthy upstream

# If you use a pod with istio sidecar (like app-2 deploy/whereami container) you should see similar results for app-1
kubectl exec -it -n istio-system test -- /bin/bash
appuser@whereami-75d8bfc59-fkd2c:/app$ curl -sH "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/zone";echo '';
projects/50123456789/zones/us-west1-c

appuser@whereami-75d8bfc59-fkd2c:/app$ curl http://whereami.app-1.svc.cluster.local/zone;echo ''
us-west1-c
us-west1-c
us-west1-c
...     # then automatic failover when the local pods are unhealthy
us-west3-c
us-west3-c
us-west3-c
```
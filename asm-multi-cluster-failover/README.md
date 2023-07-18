# Anthos Service Mesh - Multi Cluster Failover

## Setup Multi-Cluster Mesh on GKE

Following the [GKE multi-cluster mesh](https://cloud.google.com/service-mesh/docs/unified-install/gke-install-multi-cluster#zonal) instruction:

1. Create two or more GKE clusters (see [example](../common/new-project-gke.sh)) with the following features:
    * Private clusters across regions require [global access](https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters#cp-global-access) `--enable-master-global-access`
    * Also [authorized networks](https://cloud.google.com/kubernetes-engine/docs/how-to/authorized-networks) should allow cross-cluster access (control plane to control plane) for service discovery
    * All clusters should be registered to the same fleet `--fleet-project="abc"` 
    * with Workload Identity `--workload-pool "abc.svc.id.goog"` and [service mesh](../asm-deploy-terraform) configured
    * [Gateway API](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways#enable-gateway) is also recommended but not required `--gateway-api "standard"`
1. Create firewall rule(s) to allow [pod-to-pod traffic](https://cloud.google.com/service-mesh/docs/unified-install/gke-install-multi-cluster#create_firewall_rule) across GKE clusters. Something like this using cluster IP range and gke node tags:
    ```shell
    gcloud compute firewall-rules create istio-multicluster-pods \
    --allow=tcp,udp,icmp,esp,ah,sctp \
    --direction=INGRESS \
    --priority=900 \
    --source-ranges="10.104.0.0/13,10.96.0.0/13" \
    --target-tags="gke-gke-oregon-3f72abe3-node,gke-gke-slc-ae43c0f4-node" \
    --network=gke-vpc --quiet
    ```
1. Configure multi-cluster [endpoint discovery](https://cloud.google.com/service-mesh/docs/unified-install/gke-install-multi-cluster#configure_endpoint_discovery) for the service mesh
    ```shell
    # install ASM using fleet api (or use asmcli if advanced features are required)
    gcloud container fleet mesh update --management automatic --memberships gke-oregon --project abc
    gcloud container fleet mesh update --management automatic --memberships gke-slc --project abc

    # Then on all clusters enable endpoint discovery using asm-options configmap
    kubectl patch configmap/asm-options -n istio-system --type merge -p '{"data":{"multicluster_mode":"connected"}}'

    # Confirm secrets for remote clusters are now available on all clusters
    $ kubectl get secrets -n istio-system -l istio.io/owned-by=mesh.googleapis.com,istio/multiCluster=true
    NAME                                                                               TYPE     DATA   AGE
    istio-remote-secret-projects-503076227230-locations-us-west3-memberships-gke-slc   Opaque   1      15h
    ```
1. Optional: Update istio-asm-managed (or equivalent) configmap to exclude any services that should [remain local to the cluster](https://istio.io/latest/docs/ops/configuration/traffic-management/multicluster/):
    ```shell
    kubectl edit cm -n istio-system istio-asm-managed
    # it should look something like this
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
    ```

## Deploy Istio Resources and Sample App
There are a [few different ways](../asm-ingressgateway-classic) to install istio-ingressgateway, but for this example we'll use the networking.istio.io istio gateway resource and a GKE managed NLB:

```shell
# Run these commands on both clusters to create istio-ingress namespace and resources
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/base-ingressgateway.yaml

# Also create Internal NLB with global access so TLS can be terminated via ASM
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/svc-nlb-internal.yaml

# Then apply Istio resources for gateway, virtual service, and destination rule
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-multi-cluster-failover/gw-vs-dr.yaml

# And two copies of the whereami sample app into both clusters:
#   app-1 permissive mTLS with VS+DR using locality loadbalancing and primary/secondary subsets
#   app-2 strict mTLS with default mesh settings (no VS/DR)
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-1-permissive.yaml
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-2-strict.yaml
```

## Configure private zone DNS record for Istio-IngressGateway NLBs

```shell
gcloud dns --project=vpc-project record-sets create \
    whereami.example.com. --zone="example" --type="A" \
    --ttl="300" --routing-policy-type="FAILOVER" --enable-health-checking \
    --routing-policy-primary-data="projects/gke-project/regions/us-west1/forwardingRules/a321f0be283a140b596e0ec52008fae1" \
    --backup-data-trickle-ratio="0.0" --routing-policy-backup-data-type="GEO" \
    --routing-policy-backup-data="us-west1=projects/gke-project/regions/us-west3/forwardingRules/ac32a3df087494e7ca0f61c6685050ea"
```

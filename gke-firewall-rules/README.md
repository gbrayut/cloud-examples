# GKE Firewall Rules

## Overview

TODO: add introduction and link to [gce-firewall-rules](../gce-firewall-rules). See [new-project-gke.sh](../common/new-project-gke.sh) for example of creating a new project and GKE cluster.

**Note:** VPC Native clusters use [Alias IP ranges](https://cloud.google.com/vpc/docs/alias-ip#firewalls) which can impact [firewall rule matching](../gce-firewall-rules/#Overview).

TODO: add note about [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) uses Impersonation, which does NOT match as target/source service account. Still uses service account assigned when node-pool was created.

TODO: add note about [IP Masquerade](https://cloud.google.com/kubernetes-engine/docs/concepts/ip-masquerade-agent) for SNAT.

TODO: add note about [Shared VPC and Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#shared_vpc) firewall rules.

#
## GKE Default Firewall Rules

When you create a GKE cluster there are some default rules applied to the VPC. Specifically these allow all ingress on all pod ip/ports between all pods (assumed state for a Kubernetes cluster), allow master to reach kubelet on all nodes (ports 10250 and 443), and allow all tcp/udp ingress between all nodes.

```
gcloud compute firewall-rules list --project my-gke-cluster --format="table(
                name,
                network,
                direction,
                priority,
                sourceRanges.list():label=SRC_RANGES,
                allowed[].map().firewall_rule().list():label=ALLOW,
                targetTags.list():label=TARGET_TAGS)"
NAME                          NETWORK  DIRECTION  PRIORITY  SRC_RANGES      ALLOW                         TARGET_TAGS
gke-gke-iowa-58b78f12-all     gke-vpc  INGRESS    1000      10.120.0.0/13   esp,ah,sctp,tcp,udp,icmp      gke-gke-iowa-58b78f12-node
gke-gke-iowa-58b78f12-master  gke-vpc  INGRESS    1000      10.69.1.16/28   tcp:10250,tcp:443             gke-gke-iowa-58b78f12-node
gke-gke-iowa-58b78f12-vms     gke-vpc  INGRESS    1000      10.31.236.0/22  icmp,tcp:1-65535,udp:1-65535  gke-gke-iowa-58b78f12-node
```


#
## GCE Firewall Rules

For VPC Native clusters you can use the Pod Subnet (--cluster-secondary-range-name) for restricting  See [gce-firewall-rules](../gce-firewall-rules) for more details.

```bash

```

#
## Kubernetes Network Policy

https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy

https://github.com/ahmetb/kubernetes-network-policy-recipes

Example [Kubernetes Network Policy](./test-networkpolicy.yaml) manifest.

```bash
# Apply network policy to app-2 namespace
kubectl apply -f test-networkpolicy.yaml -n app-2

# View network policy applied to all namespaces
kubectl get NetworkPolicy -A 
```

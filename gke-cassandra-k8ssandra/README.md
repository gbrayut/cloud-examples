# Setting up K8ssandra for Cassandra workloads

## Overview

While Kubernetes is designed to quickly adjust to changes in workloads, you may find cases where you have brief errors or higher latency while waiting for new pods to start. Here are a few things you can use to improve performance for burstable workloads.

https://github.com/k8ssandra/k8ssandra
https://k8ssandra.io/

install via terraform
https://docs.k8ssandra.io/install/gke/


my notes for account https://docs.google.com/document/d/1MHFgMpclsVdlUDuDbROPtwrL5ECIdkYQXN9qrA0zWk8/edit?resourcekey=0-BakMPz2MC4IbkprZU7BJFg


#
## Tuning Workload and Node Autoscaler Settings

```
# https://cloud.google.com/nat/docs/gke-example
gcloud compute networks create default --project=demo2021-310119 --subnet-mode=custom --mtu=1460 --bgp-routing-mode=regional

gcloud compute networks subnets create default --project=demo2021-310119 --range=10.128.0.0/20 --network=default --region=us-central1

gcloud compute routers create nat-router --network default --region us-central1

gcloud compute routers nats create nat-config --router-region us-central1 --router nat-router --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips


# https://cloud.google.com/load-balancing/docs/health-checks#fw-rule
gcloud compute firewall-rules create fw-allow-health-checks \
    --network=default \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=35.191.0.0/16,130.211.0.0/22 \
    --target-tags=allow-health-checks \
    --rules=tcp
gcloud compute firewall-rules create fw-allow-network-lb-health-checks \
    --network=default \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=35.191.0.0/16,209.85.152.0/22,209.85.204.0/22 \
    --target-tags=allow-network-lb-health-checks \
    --rules=tcp

# https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule
gcloud compute firewall-rules create allow-ssh-ingress-from-iap \
  --direction=INGRESS \
  --action=allow \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20


gcloud beta container --project "demo2021-310119" clusters create "cassandra" --region "us-central1" \
  --no-enable-basic-auth --cluster-version "1.20.5-gke.1300" --release-channel "rapid" --enable-private-nodes \
  --master-ipv4-cidr "172.16.0.0/28" --machine-type "e2-standard-2" --image-type "COS_CONTAINERD" --disk-type "pd-standard" --disk-size "100" \
  --metadata disable-legacy-endpoints=true --num-nodes "1" --enable-stackdriver-kubernetes \
  --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --enable-ip-alias --network "projects/demo2021-310119/global/networks/default" --subnetwork "projects/demo2021-310119/regions/us-central1/subnetworks/default" \
  --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "0" --max-nodes "3" --no-enable-master-authorized-networks \
  --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver,ConfigConnector \
  --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 \
  --workload-pool "demo2021-310119.svc.id.goog" --enable-shielded-nodes --shielded-secure-boot --shielded-integrity-monitoring
```
#
## Priorityclass and Preemption

asdf

* [01-priority-classes.yaml](./01-priority-classes.yaml) Shows how to create the resources
* [02-overprovisioning.yaml](./02-overprovisioning.yaml) Shows creating a float capacity deployment
* [03-overprovisioning-tainted-nodepool.yaml](./03-overprovisioning-tainted-nodepool.yaml) Shows the same for a tainted/dedicated node pool
* [test-workload.yaml](./test-workload.yaml) Shows a simple workload for the test below

```bash
$ kubectl get storageclasses
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
premium-rwo          pd.csi.storage.gke.io   Delete          WaitForFirstConsumer   true                   83m
standard (default)   kubernetes.io/gce-pd    Delete          Immediate              true                   83m
standard-rwo         pd.csi.storage.gke.io   Delete          WaitForFirstConsumer   true                   83m

helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

# Copy k8ssandra-basic.yaml to cloud shell and then install operator via helm
todo: Use helm --create-namespace and --namespace cass-test ?
helm install cass-test k8ssandra/k8ssandra -f k8ssandra-basic.yaml

# Ignore W0430 warnings about deprecated resouce versions (their helm chart will eventually get updated
# output should look like:
W0430 00:22:02.087166    2097 warnings.go:70] apiextensions.k8s.io/v1beta1 CustomResourceDefinition is deprecated in v1.16+, unavailable in v1.22+; use apiextensions.k8s.io/v1 CustomResourceDefinition

AME: cass-test
LAST DEPLOYED: Fri Apr 30 00:22:13 2021
NAMESPACE: default
STATUS: deployed
REVISION: 1

# View grafana via web preview on another port. Login details from helm yaml file
kubectl port-forward --namespace default svc/cass-test-grafana 8090:80 >> /dev/null &

# Also test commands from https://k8ssandra.io/get-started/#verify-your-k8ssandra-installation
kubectl describe CassandraDataCenter dc1

# and https://docs.k8ssandra.io/quickstarts/site-reliability-engineer/
kubectl get secret cass-test-superuser -o jsonpath="{.data.username}" | base64 --decode ; echo
cass-test-superuser

kubectl get secret cass-test-superuser -o jsonpath="{.data.password}" | base64 --decode ; echo
CwCh6Yx2n1rktGruBso1

kubectl exec -it cass-test-dc1-us-central1-a-sts-0 -c cassandra -- sh -c 'export casspw=CwCh6Yx2n1rktGruBso1; bash'
# then in the container run whaterver C* commands you want
cassandra@cass-test-dc1-us-central1-a-sts-0:/$ nodetool -u cass-test-superuser -pw $casspw status
Datacenter: dc1
===============
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address      Load       Tokens       Owns    Host ID                               Rack
UN  10.168.0.9   228.86 KiB  256          ?       006e46d4-4938-4cbb-86f7-701ff006e5d2  us-central1-f
UN  10.168.2.11  241.67 KiB  256          ?       ecda002e-0723-4efb-ba99-873f477228b7  us-central1-b
UN  10.168.1.11  251.12 KiB  256          ?       6d77a060-96b3-460a-a86e-6669e4b5c495  us-central1-a

cassandra@cass-test-dc1-us-central1-a-sts-0:/$ nodetool -u cass-test-superuser -pw $casspw info
ID                     : 6d77a060-96b3-460a-a86e-6669e4b5c495
Gossip active          : true
Thrift active          : true
Native Transport active: true
Load                   : 251.12 KiB
Generation No          : 1619742379
Uptime (seconds)       : 2652
Heap Memory (MB)       : 605.92 / 1024.00
Off Heap Memory (MB)   : 0.00
Data Center            : dc1
Rack                   : us-central1-a
Exceptions             : 0
Key Cache              : entries 47, size 3.76 KiB, capacity 51 MiB, 3272 hits, 3533 requests, 0.926 recent hit rate, 14400 save period in seconds
Row Cache              : entries 0, size 0 bytes, capacity 0 bytes, 0 hits, 0 requests, NaN recent hit rate, 0 save period in seconds
Counter Cache          : entries 0, size 0 bytes, capacity 25 MiB, 0 hits, 0 requests, NaN recent hit rate, 7200 save period in seconds
Chunk Cache            : entries 23, size 1.44 MiB, capacity 224 MiB, 265 misses, 5545 requests, 0.952 recent hit rate, NaN microseconds miss latency
Percent Repaired       : 0.0%
Token                  : (invoke with -T/--tokens to see all 256 tokens)

# see also https://docs.k8ssandra.io/quickstarts/developer/

# Can edit the CRD to make changes to the cassandra cluser. Increasing size from 3 -> 6 or 24 will expand the cassandra nodes (really pods in the stateful set) for each rack
kubectl edit CassandraDataCenter dc1

k get pods -o wide --selector cassandra.datastax.com/rack
NAME                                READY   STATUS    RESTARTS   AGE    IP            NODE                                      NOMINATED NODE   READINESS GATES
cass-test-dc1-us-central1-a-sts-0   2/2     Running   0          65m    10.168.1.11   gke-cassandra-default-pool-9c76d3c9-ct4x   <none>           <none>
cass-test-dc1-us-central1-a-sts-1   1/2     Running   0          4m3s   10.168.1.12   gke-cassandra-default-pool-9c76d3c9-ct4x   <none>           <none>
cass-test-dc1-us-central1-b-sts-0   2/2     Running   0          65m    10.168.2.11   gke-cassandra-default-pool-a49f5225-cpnf   <none>           <none>
cass-test-dc1-us-central1-b-sts-1   1/2     Running   0          4m3s   10.168.2.13   gke-cassandra-default-pool-a49f5225-cpnf   <none>           <none>
cass-test-dc1-us-central1-f-sts-0   2/2     Running   0          65m    10.168.0.9    gke-cassandra-default-pool-5e67a467-zs9f   <none>           <none>
cass-test-dc1-us-central1-f-sts-1   1/2     Running   0          4m3s   10.168.0.11   gke-cassandra-default-pool-5e67a467-zs9f   <none>           <none>

and you can use the nodetool commands above to see when the new servers join the cassandra cluster (UJ instead of UN). It seems to add them one at a time, and takes 4-8 minutes for each node

Can also see events from the operator using
kubectl describe CassandraDataCenter dc1
```
#
## Next steps
asfd

nodes label is topology.gke.io/zone, pod label is cassandra.datastax.com/rack

use https://cloud.google.com/iap/docs/enabling-kubernetes-howto for grafana/etc

multiple datacenters in different namespaces https://github.com/datastax/cass-operator/issues/174 and https://github.com/datastax/cass-operator/pull/182/files#diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5R189 (still a WIP)
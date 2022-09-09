exit # not that kind of script
# View organizations, folders, and billing accounts
gcloud organizations list
DISPLAY_NAME                       ID  DIRECTORY_CUSTOMER_ID
example.com  10123456789              C0123abc

gcloud resource-manager folders list --organization=10123456789
DISPLAY_NAME  PARENT_NAME                            ID
demos         organizations/10123456789  40123456789
test          organizations/10123456789  50123456789

gcloud beta billing accounts list
ACCOUNT_ID            NAME                        OPEN  MASTER_ACCOUNT_ID
012345-01A0BC-67DEF8  My Billing Account  True

# variables used for create a new project
DEVSHELL_PROJECT_ID=my-gke-cluster
FOLDER=40123456789
BILLING=012345-01A0BC-67DEF8

# create project using lowercase ID and set as default in gcloud config
gcloud projects create ${DEVSHELL_PROJECT_ID,,} --name $DEVSHELL_PROJECT_ID --folder $FOLDER --set-as-default

# search for new project (also shows project number)
gcloud projects list --filter=my-gke
PROJECT_ID    NAME          PROJECT_NUMBER
my-gke-cluster  my-gke-cluster  601234567890

# update folder and billing if needed
gcloud beta billing projects link $DEVSHELL_PROJECT_ID --billing-account $BILLING
# gcloud beta projects move $DEVSHELL_PROJECT_ID --folder $FOLDER --quiet

# enable Google APIs for new project
gcloud services enable --project=$DEVSHELL_PROJECT_ID compute.googleapis.com container.googleapis.com

# create network
gcloud compute networks create gke-vpc --subnet-mode=custom --project $DEVSHELL_PROJECT_ID

# create subnets in vpc https://cloud.google.com/kubernetes-engine/docs/best-practices/networking
# See also https://googlecloudplatform.github.io/gke-ip-address-management/
gcloud compute networks subnets create gke-oregon-subnet --project=$DEVSHELL_PROJECT_ID \
    --network "projects/$DEVSHELL_PROJECT_ID/global/networks/gke-vpc" \
    --region us-west1 --range 10.28.236.0/22 \
    --secondary-range gkepods=10.96.0.0/13,gkeservices=10.68.0.0/16

gcloud compute networks subnets create gke-oregon-subnet2 --project=$DEVSHELL_PROJECT_ID \
    --network "projects/$DEVSHELL_PROJECT_ID/global/networks/gke-vpc" \
    --region us-west1 --range 10.30.236.0/22 \
    --secondary-range gkepods=10.112.0.0/13,gkeservices=10.65.0.0/16

gcloud compute networks subnets create gke-iowa-subnet --project=$DEVSHELL_PROJECT_ID \
    --network "projects/$DEVSHELL_PROJECT_ID/global/networks/gke-vpc" \
    --region us-central1 --range 10.31.236.0/22 \
    --secondary-range gkepods=10.120.0.0/13,gkeservices=10.64.0.0/16

# create clusters (for additional clusters increment third octet for master IP 10.69.x.16/28)
# see also https://cloud.google.com/sdk/gcloud/reference/container/clusters/create
gcloud beta container --project=$DEVSHELL_PROJECT_ID clusters create "gke-iowa" --region "us-central1" \
  --subnetwork "gke-iowa-subnet" --cluster-secondary-range-name "gkepods" --services-secondary-range-name "gkeservices" \
  --master-ipv4-cidr "10.69.1.16/28" --enable-private-nodes --autoscaling-profile optimize-utilization \
  --workload-pool "$DEVSHELL_PROJECT_ID.svc.id.goog" --no-enable-basic-auth --release-channel "regular" \
  --machine-type "e2-standard-4" --image-type "COS_CONTAINERD" --network "projects/$DEVSHELL_PROJECT_ID/global/networks/gke-vpc" \
  --disk-type "pd-standard" --disk-size "100" --max-pods-per-node "110" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM \
  --no-enable-intra-node-visibility --default-max-pods-per-node "110" --enable-dataplane-v2 \
  --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver \
  --enable-autoupgrade --enable-autorepair --max-surge-upgrade 3 --max-unavailable-upgrade 0 \
  --enable-autoscaling --num-nodes "1" --max-nodes=3 --min-nodes=0 \
  --enable-ip-alias --enable-shielded-nodes

# create a second node pool using two zones and spot VMs https://cloud.google.com/sdk/gcloud/reference/container/node-pools/create
gcloud container --project=$DEVSHELL_PROJECT_ID node-pools create "spot-pool" --cluster "gke-iowa" --region "us-central1" \
  --machine-type "e2-standard-2" --image-type "UBUNTU_CONTAINERD" --disk-type "pd-standard" --disk-size "100" \
  --num-nodes "1" --enable-autoscaling --min-nodes=0 --max-nodes=3 --enable-autoupgrade --enable-autorepair --max-surge-upgrade 3 \
  --max-unavailable-upgrade 0 --max-pods-per-node "110" --node-locations "us-central1-a,us-central1-f" \
  --spot --tags=gketag1,gketag2 --node-labels=example.com/fleet=spot --node-taints=example.com/testing=tainted:NoSchedule


# create namespaces and launch pods simulating two workloads with kubernetes services
kubectl create ns app-1
kubectl run test-1 -n app-1 --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.9 --port 8080 --expose

kubectl create ns app-2
# pod with node selector and toleration https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
kubectl run test-2 -n app-2 --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.9 \
  --port 8080 --expose --overrides='{"spec":{"nodeSelector":{"cloud.google.com/gke-nodepool":"spot-pool"},"tolerations":[{"key":"example.com/testing","effect":"NoSchedule","operator":"Exists"}]}}'

# describe pod to see events (TriggeredScaleUp from cluster-autoscaler)
kubectl describe pod -n app-2 test-2
# after a few minutes the pod should get scheduled to a new spot node

# test sending request from one pod to another using dns service https://kubernetes.io/docs/concepts/services-networking/service/
kubectl exec -it -n app-1 test-1 -- curl -sm 2 http://test-2.app-2.svc.cluster.local:8080
{
  "cluster_name": "gke-iowa",
  "host_header": "test-2.app-2.svc.cluster.local:8080",
  "pod_name": "test-2",
  "pod_name_emoji": "👩🏽‍❤️‍👨🏾",
  "project_id": "my-gke-cluster",
  "timestamp": "2022-09-09T00:56:55",
  "zone": "us-central1-a"
}

# cleanup single pod or both namespaces
kubectl delete pod -n app-2 test-2
kubectl delete ns app-1 app-2

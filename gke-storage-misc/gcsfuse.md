# Using GCS buckets as volumes on GKE Pods

[Cloud Storage FUSE](https://docs.cloud.google.com/storage/docs/cloud-storage-fuse/overview) can be used to read or write files in a Cloud Storage bucket as a linux file system. For GKE workloads, Google recommends using Workload Identity Federation and [gcs-fuse-csi-driver](https://github.com/GoogleCloudPlatform/gcs-fuse-csi-driver/tree/main) via fully managed [GKE Addon](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cloud-storage-fuse-csi-driver), which will create a **gcsfusecsi-node daemonset** to handle privleged operations on each node and injects an unprivliged **gke-gcsfuse-sidecar init container** inside your pods.


## Initial Setup for CSI Driver
For the full details see https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cloud-storage-fuse-csi-driver-setup#standard but the basic steps are:

```shell
PROJECT_ID=gregbray-gke
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
BUCKET_NAME=gregbray-testing
CLUSTER_NAME=gke-iowa
REGION=us-central1
NAMESPACE=test-gcs
KSA_NAME=test-gcs-access
# Note: above values should match what is used in manifests

# Check if gcsfuse CSI driver is enabled
gcloud container clusters describe $CLUSTER_NAME --region $REGION \
  --format="value(addonsConfig.gcsFuseCsiDriverConfig.enabled)"

# Enable gcsfuse CSI driver on existing cluster
gcloud container clusters update $CLUSTER_NAME --region $REGION \
  --update-addons GcsFuseCsiDriver=ENABLED

# Create bucket with https://docs.cloud.google.com/storage/docs/uniform-bucket-level-access
# More options at https://docs.cloud.google.com/sdk/gcloud/reference/storage/buckets/create
gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION \
  --uniform-bucket-level-access

# Grant KSA access to bucket (or can grant role on project/folder for all buckets)
# For read only access use roles/storage.objectViewer
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME --role "roles/storage.objectUser" \
    --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA_NAME}"

# Create Namespace and Kubernetes Service Account (KSA) for testing
kubectl create ns $NAMESPACE
kubectl create serviceaccount $KSA_NAME -n $NAMESPACE
```

## Using gcsfuse Volumes on GKE Workloads



https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cloud-storage-fuse-csi-driver

Move over https://github.com/gbrayut/cloud-examples/tree/main/k8s-gcsfuse

https://docs.cloud.google.com/storage/docs/cloud-storage-fuse/profile-based-configurations
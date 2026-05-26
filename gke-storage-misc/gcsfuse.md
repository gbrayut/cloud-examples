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
KSA_PRINCIPAL="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA_NAME}"
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --role "roles/storage.objectUser" --member "${KSA_PRINCIPAL}"

# Create Namespace and Kubernetes Service Account (KSA) for testing
kubectl create ns $NAMESPACE
kubectl create serviceaccount $KSA_NAME -n $NAMESPACE
```

## Basic gcsfuse Volumes on GKE Workloads
For basic workloads the easiest way to access files in GCS is using an [ephemeral volume mount](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cloud-storage-fuse-csi-driver-ephemeral) so you don't need to manage PersistentVolume or PersistentVolumeClaim objects. This is true for StatefulSet and Sandbox/Agent Sandbox as well, which can still use GCS as ephemeral volume instead of requiring PV and PVC resources. The [gcsfuse-ephemeral.yaml](gcsfuse-ephemeral.yaml) shows how to configure ephemeral volume access to GCS for a daemonset:

```shell
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/refs/heads/main/gke-storage-misc/gcsfuse-ephemeral.yaml

kubectl get pods -n test-gcs
NAME                               READY   STATUS    RESTARTS   AGE
basic-ephemeral-7fc5b9bf5f-v9f9v   2/2     Running   0          16s
basic-ephemeral-7fc5b9bf5f-x6mmp   2/2     Running   0          17s

# Read/write of files in GCS Bucket
kubectl exec -it -n test-gcs deploy/basic-ephemeral -c busybox -- /bin/sh \
  -c 'touch /data-this-pod/hello;ls -hal /data/** /data-this-pod/'

/data-this-pod/:
-rw-r--r--    1 root     root           0 May 22 02:42 hello    <--same file

/data/basic-ephemeral-7fc5b9bf5f-gjtls:

/data/basic-ephemeral-7fc5b9bf5f-mpm2n:
-rw-r--r--    1 root     root           0 May 22 02:42 hello    <--same file

/data/this-is-gregbray-testing:     <--empty folder from root of bucket
```

## Statefulset gcsfuse Volumes on GKE Workloads
For more advanced workloads like Statefulset, you can still use ephemeral volume mounts, or switch to a [Persistent Volume](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cloud-storage-fuse-csi-driver-pv). Usually that means having a PV for each workload (potentially backed by a shared bucket) and a single shared PVC for all the pods. The [gcsfuse-pvc-sts.yaml](gcsfuse-pvc-sts.yaml) shows what that would look like for a Statefulset but similar approach would work for daemonset as well:

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-storage-misc/gcsfuse-pvc-sts.yaml

kubectl get pods -n test-gcs
NAME                                 READY   STATUS    RESTARTS   AGE
stateful-whereami-0                  2/2     Running   0          73s
stateful-whereami-1                  2/2     Running   0          69s
stateful-whereami-2                  2/2     Running   0          64s

# Read/write of files in GCS Bucket
kubectl exec -it -n test-gcs pod/stateful-whereami-1 -c whereami -- /bin/sh \
  -c 'touch /data-this-pod/hello;ls -hal /data/test-gcs/** /data-this-pod'

/data-this-pod:
-rw-r--r-- 1 appuser appuser 0 May 22 02:32 hello

/data/test-gcs/stateful-whereami-0:

/data/test-gcs/stateful-whereami-1:
-rw-r--r-- 1 appuser appuser 0 May 22 02:32 hello

/data/test-gcs/stateful-whereami-2:


# View pv and pvc resources
kubectl get pv,pvc -n test-gcs
NAME                                    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                            STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE

persistentvolume/stateful-whereami-pv   10Gi       RWX            Retain           Bound    test-gcs/stateful-whereami-pvc                  <unset>                          72m

NAME                                          STATUS   VOLUME                 CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/stateful-whereami-pvc   Bound    stateful-whereami-pv   10Gi       RWX                           <unset>                 72m
```

## GKE Sandbox and gcsfuse Volumes
Because the gcs-fuse-csi-driver runs the privliged operations in a separate daemonset, workloads using [GKE Sandbox](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/sandbox-pods) should still be able to access files via gcsfuse volume mounts. In most cases the ephemeral mounts will be the easiest approach, but PV+PVC approach should also work. The [gcsfuse-sandbox-ephemeral.yaml](gcsfuse-sandbox-ephemeral.yaml) shows using ephemeral gscsfuse volumes on `runtimeClassName: gvisor` workloads:

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-storage-misc/gcsfuse-sandbox-ephemeral.yaml

kubectl get pods -n test-gcs
NAME                                 READY   STATUS    RESTARTS   AGE
sandbox-ephemeral-67dc7db79c-x48zq   2/2     Running   0          2m13s

kubectl exec -it -n test-gcs deploy/sandbox-ephemeral -c busybox -- /bin/sh -c 'touch /data-this-pod/hello;ls -hal /data/** /data-this-pod/'
/data-this-pod/:
-rw-r--r--    1 root     root           0 May 22 02:48 hello

/data/sandbox-ephemeral-67dc7db79c-mt24f:
-rw-r--r--    1 root     root           0 May 22 02:48 hello

/data/this-is-gregbray-testing:
```

## GKE Agent Sandbox and gcsfuse Volumes

The [gcsfuse-agentsandbox-example.yaml](gcsfuse-agentsandbox-example.yaml) and [gcsfuse-agentsandbox-warmpool.yaml](gcsfuse-agentsandbox-warmpool.yaml) shows using ...

```shell
$ kubectl get pvc,pv,pod,sandbox -n test-gcs -o wide
NAME                                          STATUS   VOLUME                 CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE     VOLUMEMODE
persistentvolumeclaim/agentsandbox-pool-pvc   Bound    agentsandbox-pool-pv   10Gi       RWX                           <unset>                 2m49s   Filesystem

NAME                                    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                            STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE     VOLUMEMODE
persistentvolume/agentsandbox-pool-pv   10Gi       RWX            Retain           Bound    test-gcs/agentsandbox-pool-pvc                  <unset>                          2m50s   Filesystem

NAME                              READY   STATUS    RESTARTS   AGE     IP              NODE                                NOMINATED NODE   READINESS GATES
pod/agentsandbox-warmpool-q4hbw   2/2     Running   0          2m48s   10.27.128.131   gke-gke-iowa-gvisor-89761852-dlkh   <none>           <none>
pod/agentsandbox-warmpool-xbx5s   2/2     Running   0          2m49s   10.27.128.130   gke-gke-iowa-gvisor-89761852-dlkh   <none>           <none>
pod/agentsandbox-warmpool-xxxgq   2/2     Running   0          2m47s   10.27.128.132   gke-gke-iowa-gvisor-89761852-dlkh   <none>           <none>

NAME                                                  AGE
sandbox.agents.x-k8s.io/agentsandbox-warmpool-q4hbw   2m49s
sandbox.agents.x-k8s.io/agentsandbox-warmpool-xbx5s   2m49s
sandbox.agents.x-k8s.io/agentsandbox-warmpool-xxxgq   2m49s

$ kubectl describe sandboxclaim/my-sandbox-claim -n test-gcs
Name:         my-sandbox-claim
Namespace:    test-gcs
Labels:       <none>
Annotations:  agents.x-k8s.io/controller-first-observed-at: 2026-05-22T22:28:42.31550947Z
API Version:  extensions.agents.x-k8s.io/v1alpha1
Kind:         SandboxClaim
Metadata:
  Creation Timestamp:  2026-05-22T22:28:42Z
  Generation:          1
  Resource Version:    1779489050443263018
  UID:                 9292a470-bed4-41e4-863f-45647856e8f4
Spec:
  Sandbox Template Ref:
    Name:    agentsandbox-template
  Warmpool:  default
Status:
  Conditions:
    Last Transition Time:  2026-05-22T22:30:50Z
    Message:               Pod is Ready; Service Exists
    Observed Generation:   2
    Reason:                DependenciesReady
    Status:                True
    Type:                  Ready
  Sandbox:
    Name:  agentsandbox-warmpool-xbx5s
    Pod I Ps:
      10.27.128.130
Events:  <none>

$ SANDBOX_POD=$(kubectl get -n test-gcs sandboxclaim/my-sandbox-claim -o jsonpath='{.status.sandbox.name}')
$ kubectl exec -it -n test-gcs $SANDBOX_POD -c my-container -- /bin/sh -c 'touch /data-this-pod/hello;ls -hal /data/test-gcs/** /data-this-pod'
/data-this-pod:
-rw-r--r--    1 1000     1000           0 May 22 22:34 hello


/data/test-gcs/agentsandbox-warmpool-q4hbw:

/data/test-gcs/agentsandbox-warmpool-xbx5s:
-rw-r--r--    1 1000     1000           0 May 22 22:34 hello

/data/test-gcs/agentsandbox-warmpool-xxxgq:
```

## TODO:
https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cloud-storage-fuse-csi-driver

Move over https://github.com/gbrayut/cloud-examples/tree/main/k8s-gcsfuse

https://docs.cloud.google.com/storage/docs/cloud-storage-fuse/profile-based-configurations

https://github.com/GoogleCloudPlatform/gcs-fuse-csi-driver/issues/59#issuecomment-1716967172

example for manual init container when auto token mount is disabled?

file bug for persistentVolumeReclaimPolicy: Delete not working? First confirm expectations using another volume type.

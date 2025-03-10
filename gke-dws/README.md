# GKE Dynamic Workload Scheduler(DWS)

DRAFT notes on configuring GKE workloads to use [Dynamic Workload Scheduler](https://cloud.google.com/blog/products/compute/introducing-dynamic-workload-scheduler).

Flex Mode: requests nodes that run up to 7 days (but you can terminate the instances early or whenever your workload is finished). Small instance counts for short durations in large regions are usually approved in less than 5 minutes, where as larger/longer requests may take a few hours to approve.

Calendar Mode: Based on future reservations with fixed duration (minimum 7 day commitment, no early termination). These require review from the capacity team and may take 2-3 days to approve.

## Increase Quota

DWS Flex mode requires `compute.googleapis.com/preemptible_nvidia_h100_gpu` or similar quota for the region you plan on using. You can request [quota increase](https://console.cloud.google.com/iam-admin/quotas?pageState=(%22allQuotasTable%22:(%22f%22:%22%255B%257B_22k_22_3A_22Metric_22_2C_22t_22_3A10_2C_22v_22_3A_22_5C_22compute.googleapis.com%252Fpreemptible_nvidia_h100_gpus_5C_22_22_2C_22s_22_3Atrue_2C_22i_22_3A_22metricName_22%257D%255D%22))) for example 24 would allow up to 3 a3-highgpu-8g (3*8=24). Also note that even though DWS flex requires preemptible quota, when provisioning VMs it uses on-demand instances.

Once your regional quota is available, you can test it using a GCE Instance:

```
# GCE testing of DWS instance. Provisions an on-demand VM that will terminate after the max-run-duration has completed.
gcloud compute instances create instance-1 \
    --zone=us-central1-a \
    --machine-type=a3-highgpu-8g \
    --max-run-duration=1h \
    --instance-termination-action=DELETE \
    --maintenance-policy=TERMINATE \
    --reservation-affinity=none \
    --network-interface "nic-type=GVNIC,network=default,subnet=default,no-address"
```

## Configure Node Pool

Usually best to manually configure node pool for DWS, but you can also use Node Auto Provisioner ([NAP with DWS](https://cloud.google.com/kubernetes-engine/docs/how-to/provisioningrequest#nap)).

Note: DWS requires specific settings (**--num-nodes=0**) and is not compatible with others (like **--placement-type=COMPACT** which is always enabled by default).

```
# https://cloud.google.com/kubernetes-engine/docs/how-to/provisioningrequest#create-node-pool
gcloud container node-pools create dws-h100 \
    --cluster=gke-iowa \
    --location=us-central1 \
    --enable-queued-provisioning \
    --accelerator="type=nvidia-h100-80gb,count=8,gpu-driver-version=latest" \
    --machine-type=a3-highgpu-8g \
    --enable-autoscaling  \
    --num-nodes=0   \
    --total-max-nodes 10  \
    --location-policy=ANY  \
    --reservation-affinity=none  \
    --no-enable-autorepair
```

## Deploy workloads:

DWS is designed to work with Batch orchestration frameworks like [Kueue](https://cloud.google.com/kubernetes-engine/docs/how-to/provisioningrequest#run-batch), but also supports standard Kubernetes [Jobs](https://cloud.google.com/kubernetes-engine/docs/how-to/provisioningrequest#configure-pods-provisioningrequest).

TODO: create dws-test-job.yaml

See also [DWS for Kubernetes Deployment](./zzz_dws-test-deploy.yaml) example, however since DWS Flex was designed for batch workloads, serving/infrence workloads are usually better off using DWS Calendar Mode.

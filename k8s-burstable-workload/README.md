# Improving pod creation time for burstable workloads

## Overview

While Kubernetes is designed to quickly adjust to changes in workloads, you may find cases where you have brief errors or higher latency while waiting for new pods to start. Here are a few things you can use to improve performance for burstable workloads:

Tuning node settings (often very difficult, unless you just )
default autoscaler doesn't have many options https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler and using a custom autoscaler ...


Adjusting HPA for additional capacity (requires tuning all workloads) or using custom/external metrics
https://cloud.google.com/kubernetes-engine/docs/concepts/custom-and-external-metrics

or combining HPA and VPA using the new [Multidimensional Pod Autoscaler](https://cloud.google.com/blog/topics/developers-practitioners/scaling-workloads-across-multiple-dimensions-gke).

Overprovisioning (creates float capacity) helps reduce the pod creation time for deployments and cronjobs. Can also use a [tainted node pool](https://cloud.google.com/kubernetes-engine/docs/how-to/node-taints#creating_a_node_pool_with_node_taints) to better control resources that are available for specific workloads.

#
## Priorityclass and Preemption

pause Pods for float capacity and spinning up nodes upfront.
https://cloud.google.com/solutions/best-practices-for-running-cost-effective-kubernetes-applications-on-gke

pause pods require setting up priorityclasses so you can configure preemption
https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/

preemption
https://medium.com/@mohaamer5/kubernetes-pod-priority-and-preemption-943c58aee07d

```bash
$ kubectl get priorityclass
NAME                      VALUE        GLOBAL-DEFAULT   AGE
cluster-critical          1000000000   false            27m
high-priority             1000000      false            27m
low-priority              1000         false            27m
node-critical             5000000      false            27m
normal-priority           50000        true             27m
overprovisioning          1            false            135m
system-cluster-critical   2000000000   false            3h22m
system-node-critical      2000001000   false            3h22
```
## Example of using floating capacity
```bash
$ kubectl get pods -n overprovisioning -w
# This shows two low priority pods running (created 10 seconds ago), ready to be evicted if a higher priority workload is admitted to the cluster
NAME                                       READY   STATUS    RESTARTS   AGE
overprovisioning-highmem-65475f59c7-mzszm   1/1     Running   0          10s
overprovisioning-highmem-65475f59c7-w8cs4   1/1     Running   0          10s

# Here is the test workload with 3 new pods getting admitted, and the exiting overprovisioning pods getting terminated (with new 2 pods overprovisioning pods pending)
test-workload-fdcdd8df9-wnkrk               0/1     Pending   0          0s
test-workload-fdcdd8df9-2wg8v               0/1     Pending       0          0s
test-workload-fdcdd8df9-qhw98               0/1     Pending       0          0s
overprovisioning-highmem-65475f59c7-mzszm   1/1     Terminating   0          2m17s
overprovisioning-highmem-65475f59c7-8jqdl   0/1     Pending       0          0s
overprovisioning-highmem-65475f59c7-w8cs4   1/1     Terminating   0          2m17s
overprovisioning-highmem-65475f59c7-79gkv   0/1     Pending       0          0s
overprovisioning-highmem-65475f59c7-w8cs4   0/1     Terminating   0          2m18s

# Here we see after 2 seconds one of the new workload containers has been scheduled (ContainerCreating) to an existing node and starts Running after just 3 seconds total 
test-workload-fdcdd8df9-2wg8v               0/1     ContainerCreating   0          2s
test-workload-fdcdd8df9-2wg8v               1/1     Running             0          3s

# Same for the second container, which is fully running with in 7s
test-workload-fdcdd8df9-wnkrk               0/1     Pending             0          6s
test-workload-fdcdd8df9-wnkrk               0/1     ContainerCreating   0          6s
test-workload-fdcdd8df9-wnkrk               1/1     Running             0          7s

# Since there was only enough floating capacity for the first two workload pods, the third had to wait for a new node to be created.
# It started running after 52 seconds along side the new overprovisioning pods
test-workload-fdcdd8df9-qhw98               0/1     ContainerCreating   0          47s
overprovisioning-highmem-65475f59c7-8jqdl   0/1     ContainerCreating   0          48s
overprovisioning-highmem-65475f59c7-79gkv   0/1     ContainerCreating   0          50s
test-workload-fdcdd8df9-qhw98               1/1     Running             0          52s
overprovisioning-highmem-65475f59c7-8jqdl   1/1     Running             0          53s
overprovisioning-highmem-65475f59c7-79gkv   1/1     Running             0          53s
```

## Next steps
tune size of pause pods resource requests to match expected burst workload pods for each node pool

use cronjob to adjust deployment scale during work hours, tune HPA using custom metrics, or even use cluster proportional autoscaler
https://medium.com/scout24-engineering/cluster-overprovisiong-in-kubernetes-79433cb3ed0e

ContainerCreating depends on if workload images are cached, what the pull policy is set to, and how large the image is.

monitoring pod creation time? Show kubectl commands?

mention node autoprovisioning also adding extra time?
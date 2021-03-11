# Improving pod creation time for burstable workloads

## Overview

While Kubernetes is designed to quickly adjust to changes in workloads, you may find cases where you have brief errors or higher latency while waiting for new pods to start. Here are a few things you can use to improve performance for burstable workloads.

#
## Tuning Workload and Node Autoscaler Settings

Dynamic workloads should use a Horizontal Pod Autoscaler so they can scale out with additional resources when needed. CPU/Memory usage are most often used, but you may find [custom or external metrics](https://cloud.google.com/kubernetes-engine/docs/concepts/custom-and-external-metrics) that better represent the amount of work pending and can scale better or faster than waiting for pods to cross a resource threshold. Also those scaling thresholds can be adjusted as a way to build in sufficient headroom for bursts while waiting for new pods to be created. But be aware that unless the pods use [Guarenteed QoS](https://www.replex.io/blog/everything-you-need-to-know-about-kubernetes-quality-of-service-qos-classes) (resource limits=resource requests) you may be oversubscribing nodes and not have free resources available for the pods to use during bursts.

The [GKE cluster autoscaler](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler) does have some settings you can use to tune node level utilization, and in rare cases it may make sense to replace the built in Autoscaler with a custom solution. But while possible, using a custom node Autoscaler is outside the scope of GKE support, and you usually should start with tuning deployments or possibly creating a [dedicated node pool](https://cloud.google.com/kubernetes-engine/docs/how-to/node-taints#creating_a_node_pool_with_node_taints) to better control resources and scaling used by specific workloads.

And if you happen to have a more predictable workload or event, like a daily spike or are expecting a large shift in traffic, manual or automated pre-scaling by pinning the HPA minReplica count to a higher value might be a viable solution. Once the spike has subsided you can change back to steady state settings and the cluster will adjust accordingly.

#
## Priorityclass and Preemption

Another way to improve pod startup times is by creating a special [buffer/over-provisioning](https://cloud.google.com/solutions/best-practices-for-running-cost-effective-kubernetes-applications-on-gke#autoscaler_and_over-provisioning) deployment and implementing Priority Classes for your workloads. This deployment can dynamically adjust how much floating capacity is available across the node pool, and can greatly reduce the time spent waiting for new pods to be scheduled and created (from +60s to <10s). An over-provisioning deployment uses low priority pause pods that do nothing and will be [preempted/evicted](https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/) when another higher priority workload is scheduled.

You can find an example of setting up the [pod priority and preemption](https://medium.com/@mohaamer5/kubernetes-pod-priority-and-preemption-943c58aee07), which requires creating additional priorityclasses beyond the default system-cluster-critical and system-node-critical values.

* [01-priority-classes.yaml](./01-priority-classes.yaml) Shows how to create the resources
* [02-overprovisioning.yaml](./02-overprovisioning.yaml) Shows creating a float capacity deployment
* [03-overprovisioning-tainted-nodepool.yaml](./03-overprovisioning-tainted-nodepool.yaml) Shows the same for a tainted/dedicated node pool
* [test-workload.yaml](./test-workload.yaml) Shows a simple workload for the test below

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
### Example of using floating capacity
Once the floating capacity is in place, you can watch during a deployment to see how new pods are scheduled:
```bash
$ kubectl get pods -n overprovisioning -w
# This shows two low priority pods running (created 10 seconds ago), ready to be evicted if a higher priority workload is admitted to the cluster
NAME                                       READY   STATUS    RESTARTS   AGE
overprovisioning-highmem-65475f59c7-mzszm   1/1     Running   0          10s
overprovisioning-highmem-65475f59c7-w8cs4   1/1     Running   0          10s

# Here is the test workload with 3 new pods getting admitted, and the existing overprovisioning pods getting terminated (with new 2 pods overprovisioning pods pending) to make room for test-workload pods
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

# Since there was only enough floating capacity for the first two workload pods, the third had to wait for a new node to be created by the cluster autoscaler
# It started running after 52 seconds along side the new overprovisioning pods
test-workload-fdcdd8df9-qhw98               0/1     ContainerCreating   0          47s
overprovisioning-highmem-65475f59c7-8jqdl   0/1     ContainerCreating   0          48s
overprovisioning-highmem-65475f59c7-79gkv   0/1     ContainerCreating   0          50s
test-workload-fdcdd8df9-qhw98               1/1     Running             0          52s
overprovisioning-highmem-65475f59c7-8jqdl   1/1     Running             0          53s
overprovisioning-highmem-65475f59c7-79gkv   1/1     Running             0          53s
```

## Next steps
The above example used pause pods that were about the same size as the expected busting workload, but you will have to tune that deployment for your specific needs and cost conserns. If you happen to have an existing low priority preemptable workload you can use that instead, or even use a cronjob to adjust the fixed-size scale of the overprovisioning deployment so it is ramped up only during your key business hours. Driving the size of the floating capacity by using an HPA with custom metrics is another option, or even using the [cluster-proportional-autoscaler](https://medium.com/scout24-engineering/cluster-overprovisiong-in-kubernetes-79433cb3ed0e) instead of an HPA so it scales based on the overall size of the cluster.

If you then find that the ContainerCreating stage is still taking a significant amount of time, it may mean that nodes are spending time pulling down the container images from the registry. You can look at optimizing the size of your container images, and making sure that the container pull policy is set to allow using a cached copy of the image when appropriate.

monitoring pod creation time? Show kubectl commands?

mention node autoprovisioning also adding extra time?

or combining HPA and VPA using the new [Multidimensional Pod Autoscaler](https://cloud.google.com/blog/topics/developers-practitioners/scaling-workloads-across-multiple-dimensions-gke).

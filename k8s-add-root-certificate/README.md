# Add Root Certificate To Trusted Roots On GKE Nodes

## Overview

If you try and use a container registry with a private or self signed TLS certificate, you likely will see `Error: ErrImagePull` and `x509: certificate signed by unknown authority` errors. This example shows how to work around those issues by initializing GKE nodes to trust your public root certificate.

You will need a private registry and Kubernetes cluster for testing. See [Setup notes](./setup.md) and [common steps](../common/) for examples.

#
## Replicate error using test deployment

This example uses a [test-deploy.yaml](./test-deploy.yaml) deployment with `image: test-registry:443/test-debian` served from our test registry.

```bash
kubectl apply -f ./test-deploy.yaml
kubectl get pods -l 'app=test-private-image' -o wide
kubectl describe pods -l 'app=test-private-image' 

# On initial testing you should see the following error:
Events:
  Type     Reason     Age                    From               Message
  ----     ------     ----                   ----               -------
  Normal   Scheduled  4m34s                  default-scheduler  Successfully assigned default/test-private-image-5db84f8d78-44rkg to gke-test-cluster-default-pool-82a3bf38-ffs3
  Normal   Pulling    3m4s (x4 over 4m33s)   kubelet            Pulling image "test-registry:443/test-debian"
  Warning  Failed     3m4s (x4 over 4m33s)   kubelet            Failed to pull image "test-registry:443/test-debian": rpc error: code = Unknown desc = failed to pull and unpack image "test-registry:443/test-debian:latest": failed to resolve reference "test-registry:443/test-debian:latest": failed to do request: Head https://test-registry:443/v2/test-debian/manifests/latest: x509: certificate signed by unknown authority
  Warning  Failed     3m4s (x4 over 4m33s)   kubelet            Error: ErrImagePull
  Normal   BackOff    2m50s (x6 over 4m33s)  kubelet            Back-off pulling image "test-registry:443/test-debian"
  Warning  Failed     2m39s (x7 over 4m33s)  kubelet            Error: ImagePullBackOff
```

This is due to the certificate not being trusted by nodes in the cluster. You can manually validate the fix on individual nodes using:

```bash
# Use gcloud to SSH into a GKE node
gcloud compute ssh gke-test-cluster-default-pool-82a3bf38-63d7 --tunnel-through-iap
# Paste contents of certs/domain.crt file into /etc/ssl/certs/ file
sudo vim /etc/ssl/certs/test-registry.crt 
# Update trusted certificates
sudo update-ca-certificates
# Restart any running services that need to use the new root
sudo systemctl restart docker containerd
```

#
## Bootstrap GKE nodes using DaemonSet

GKE currently recomends using DaemonSets to [bootstrap GKE nodes](https://cloud.google.com/solutions/automatically-bootstrapping-gke-nodes-with-daemonsets). The solution here is based on the [GKE Node Initializer](https://github.com/GoogleCloudPlatform/solutions-gke-init-daemonsets-tutorial) example along with https://github.com/samos123/gke-node-customizations example. 

You will need to update the ConfigMap in [node-initializer.yaml](./node-initializer.yaml) to replace `new-trusted-ca.crt` with your new public root certificate, and then when you apply the DaemonSet it runs an init container on all nodes to configure the new trusted root.

```bash
# Apply yaml
$ kubectl apply -f ./node-initializer.yaml
configmap/entrypoint created
daemonset.apps/node-initializer created

# See if pods are running
$ kubectl get pods -o wide
NAME                                ... STATUS  ... NODE                                       
node-initializer-4n2w7              ... Running ... gke-test-cluster-default-pool-82a3bf38-s1q5
node-initializer-f9pl4              ... Running ... gke-test-cluster-default-pool-82a3bf38-0g5s
test-private-image-6fcfc4864f-2ctjp ... Running ... gke-test-cluster-default-pool-82a3bf38-s1q5
test-private-image-6fcfc4864f-6fntb ... Running ... gke-test-cluster-default-pool-82a3bf38-0g5s

# If there are any issues, check for errors using:
kubectl describe pod node-initializer-...

# Check the container logs to see additional details on initializing nodes
$ kubectl logs node-initializer-wp58j -c node-initializer
Copying new trusted root CAs
Running update-ca-certificates on node
Updating certificates in /etc/ssl/certs...
140 added, 0 removed; done.
Running hooks in /etc/ca-certificates/update.d...
done.
Restart docker and containerd
Finished initializing node

# If you need to re-run the initializer while testing, first delete the existing DaemonSet using
kubectl delete daemonset node-initializer
# Then re-run the apply command to update the ConfigMap and DaemonSet
```

#
## Known Issues

Since pods can be scheduled to nodes before the DaemonSet has finished initializing, you may still see ErrImagePull and ImagePullBackoff errors. You can try to use https://github.com/uswitch/nidhogg to taint nodes and prevent pods from being scheduled, but that is also implemented via DaemonSet and may still have race conditions. There are kubelet flags for registering nodes with taints (not available in GKE) or you can use a [mutating webhook](https://github.com/uswitch/nidhogg/issues/24#issuecomment-680956438).

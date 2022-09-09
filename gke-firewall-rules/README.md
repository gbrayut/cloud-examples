# GKE Firewall Rules

## Overview

See [Setup notes](./setup.md) and [common steps](../common/) for examples.

#
## Kubernetes Network Policy

https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy

This example uses a [test-deploy.yaml](./test-deploy.yaml) deployment with `image: test-registry:443/test-debian` served from our test registry.

```bash
gcloud container node-pools describe test3

$ kubectl exec -it -n app-1 test-1 -- curl -vsm 2 http://test-2.app-2.svc.cluster.local:8080
*   Trying 10.64.254.81:8080...
* Connection timed out after 2000 milliseconds
* Closing connection 0
command terminated with exit code 28


kubectl run test --labels="testing=allow-app-1" -n default --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.9

kubectl run echo9090 -n app-2 --env="PORT=9090" --image=docker.io/inanimate/echo-server --port 9090 --expose



kubectl exec -n app-2 test-2 -it -- curl -vH "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/?recursive=true



$ kubectl exec -n app-2 test-2 -it -- curl -vsm 2 http://echo9090:9090
*   Trying 10.64.157.98:9090...
* Connection timed out after 2000 milliseconds
* Closing connection 0
command terminated with exit code 28

kubectl exec -n app-1 test-1 -it -- curl -vm 1 http://test-2.app-2.svc.cluster.local:8080
kubectl exec -n app-1 test-1 -it -- curl -vm 1 http://echo9090.app-2.svc.cluster.local:9090
kubectl exec -n app-2 test-2 -it -- curl -vm 1 http://echo9090:9090



* Could not resolve host: test0b.app-2.svc.cluster.local

* Resolving timed out after 1000 milliseconds


```

labels:
  goog-gke-node: ''

tags:
  gke-gke-iowa-a774302b-node

#
## Known Issues


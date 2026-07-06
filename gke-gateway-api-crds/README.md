# Managing Gateway API Versions in GKE Clusters

When using [GKE Gateway Classes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways) the Kubernetes Gateway API Custom Resource Definition versions will automatically be managed based on the [version of GKE](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities) being used by the cluster. This ensures the GKE Gateway Controller functions correctly and that any newer versions are validated before they are deployed into the GKE release channels (usually starting a month or so after the upstream release).
This effectively means when a GKE cluster is configured using `--gateway-api=standard` any attempts to try and modify those CRDs (including InferencePool from [inference extension](https://gateway-api-inference-extension.sigs.k8s.io/)) will get reverted. In the case of experimental APIs, they will be rejected by the `enforce-gateway-standard-channel` admission policy:

> The customresourcedefinitions "tcproutes.gateway.networking.k8s.io" is invalid: ValidatingAdmissionPolicy 'enforce-gateway-standard-channel' with binding 'enforce-gateway-standard-channel-binding' denied request: All Gateway API CRDs must belong to the 'standard' channel. Experimental CRDs are not permitted.

## Applying newer InferencePool CRD to GKE 1.36

GKE 1.36.0 currently pins InferencePool to `bundle-version: v1.4.0` and Gateway API CRDs to `component-version: 1.5.0-gke.3505` as that is what is required for [GKE Inference Gateway](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway). If you plan on using a different Inference Gateway implementation that needs a strictly newer version of the InferencePool CRD you can [self-upgrade](https://github.com/GoogleCloudPlatform/gke-gateway-api/tree/main/self-upgrades) to a patched version of the upstream release using this sample [kustomize.yaml](./inference-pool-1-5-0/kustomization.yaml) file.

### WARNING: The NewerRevision label means if/when the GKE pinned version is updated to a newer version than what is specified in your components.gke.io/component-version annotation, the newer pinned version will be applied.

Also note that modifying pinned CRDs could cause issues with GKE Gateway or other Gateway API implementations.

```shell
# can use GitHub repo or local folder (SOURCE=~/cloud-examples/gke-gateway-api-crds/inference-pool-1-5-0/)
SOURCE="github.com/gbrayut/cloud-examples/gke-gateway-api-crds/inference-pool-1-5-0"

# Dry run: local rendering of resource yaml
$ kubectl kustomize $SOURCE | head -n 10
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    api-approved.kubernetes.io: https://github.com/kubernetes-sigs/gateway-api-inference-extension/pull/1173
    components.gke.io/component-version: 1.5.0-gke.9999     <--- patched version
    inference.networking.k8s.io/bundle-version: v1.5.0
  labels:
    addonmanager.kubernetes.io/mode: NewerRevision          <--- added label
  name: inferencepools.inference.networking.k8s.io

# Compare rendered manifest against existing resources in a cluster
$ kubectl diff -k $SOURCE
diff -u -N /tmp/LIVE-1035043144/apiextensions.k8s.io.v1.CustomResourceDefinition..inferencepools.inference.networking.k8s.io /tmp/MERGED-1509207462/apiextensions.k8s.io.v1.CustomResourceDefinition..inferencepools.inference.networking.k8s.io
--- /tmp/LIVE-1035043144/apiextensions.k8s.io.v1.CustomResourceDefinition..inferencepools.inference.networking.k8s.io	2026-07-01 09:30:09.132196094 -0600
+++ /tmp/MERGED-1509207462/apiextensions.k8s.io.v1.CustomResourceDefinition..inferencepools.inference.networking.k8s.io	2026-07-01 09:30:09.136196134 -0600
@@ -4,9 +4,9 @@
   annotations:
     api-approved.kubernetes.io: https://github.com/kubernetes-sigs/gateway-api-inference-extension/pull/1173
     components.gke.io/component-name: gateway-api-crds
-    components.gke.io/component-version: 1.5.0-gke.3505
+    components.gke.io/component-version: 1.5.0-gke.9999
     components.gke.io/layer: addon
-    inference.networking.k8s.io/bundle-version: v1.4.0
+    inference.networking.k8s.io/bundle-version: v1.5.0
   creationTimestamp: "2026-07-01T15:30:00Z"
   generation: 1
   labels:

# Apply changes to cluster (server side apply and force-conflicts prevents warning for last-applied-configuration annotation)
$ kubectl apply -k $SOURCE --server-side --force-conflicts
customresourcedefinition.apiextensions.k8s.io/inferencepools.inference.networking.k8s.io serverside-applied

# Wait a few minutes and then verify changes were applied and not reconciled back to previous version
$ kubectl get crd inferencepools.inference.networking.k8s.io -o yaml | head -n 9
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    api-approved.kubernetes.io: https://github.com/kubernetes-sigs/gateway-api-inference-extension/pull/1173
    components.gke.io/component-name: gateway-api-crds
    components.gke.io/component-version: 1.5.0-gke.9999
    components.gke.io/layer: addon
    inference.networking.k8s.io/bundle-version: v1.5.0
```
To revert back to the GKE managed version of InferencePool CRD, simply delete the current version and it will immediately reconcile back to the pinned version.

```shell
$ kubectl delete crd inferencepools.inference.networking.k8s.io

$ kubectl get crd inferencepools.inference.networking.k8s.io -o yaml | grep component-version
    components.gke.io/component-version: 1.5.0-gke.3505
```

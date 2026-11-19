# OSS Istio on GKE Sandbox (Gvisor)

When using upstream Istio on GKE Sandbox (gvisor) node pools, Istio must be installed with the [CNI node agent](https://istio.io/latest/docs/setup/additional-setup/cni/#installing-with-helm) so that it injects the **istio-validation** init container (which does not require any pod privleges) instead of **istio-init**. Here are some general instructions:

```shell
# install istio with privileged istio-cni-node daemonset and unprivileged istio-validation initContainers
helm repo add istio https://blob.istio.io/istio-release/charts
helm repo update
helm install istio-base istio/base --version "1.32.0" -n istio-system \
  --create-namespace --set global.platform=gke --set defaultRevision=default
helm install istio-cni istio/cni --version "1.32.0" -n istio-system \
  --wait --set global.platform=gke
helm install istiod istio/istiod --version "1.32.0" -n istio-system \
  --wait --set pilot.cni.enabled=true --set global.platform=gke

# check for istio-cni-node-.... pods on each node, and tail their logs if there are any issues
kubectl get pod -n istio-system -o wide

# apply test workloads for gvisor and microvm
kubectl create ns test-istio
kubectl label namespace test-istio istio-injection=enabled
kubectl apply -f sandbox-istio-gvisor.yaml

kubectl get pod -n test-istio -o wide
```

# OSS Istio on GKE Sandbox (Microvm)

If the GKE cluster is also using kata containers (microvm), those cannot use CNI based init and instead must have the in-pod privileged istio-init. You can [manually inject](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/#manual-sidecar-injection) the containers or use a customized injection template. See **sidecarInjectorWebhook.templates.kata-init** section in [sandbox-istiod-values.yaml](./sandbox-istiod-values.yaml) and **inject.istio.io/templates** annotation in [sandbox-istio-microvm.yaml](./sandbox-istio-microvm.yaml):

```shell
# update istiod to include a kata-init injector that uses istio-init
helm upgrade istiod istio/istiod -n istio-system --version "1.32.0" \
  -f sandbox-istiod-values.yaml --wait

# deploy microvm sandbox with inject.istio.io/templates annotation
kubectl apply -f sandbox-istio-microvm.yaml

kubectl get pod -n test-istio -o wide
```

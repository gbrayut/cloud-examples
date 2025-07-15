#

```
# https://gateway.envoyproxy.io/docs/tasks/quickstart/
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.4.2 -n envoy-gateway-system --create-namespace
# settings at https://github.com/envoyproxy/gateway/tree/main/charts/gateway-helm
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

# Apply eg GatewayClass and sample app for testing
kubectl create ns test
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.4.2/quickstart.yaml -n test

```
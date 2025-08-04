# Envoy Gateway in GKE

[Envoy Gateway](https://gateway.envoyproxy.io/docs/) is an open source project for managing Envoy Proxy as a standalone or Kubernetes-based application gateway. Kubernetes Gateway API resources are used to dynamically provision and configure the managed Envoy Proxies.

```shell
# https://gateway.envoyproxy.io/docs/tasks/quickstart/
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.4.2 -n envoy-gateway-system --create-namespace
# settings at https://github.com/envoyproxy/gateway/tree/main/charts/gateway-helm
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

# Apply eg GatewayClass and sample app for testing
kubectl create ns test
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.4.2/quickstart.yaml -n test
```

# Basic L7 Envoy Gateway

The [01-basic-example.yaml](./01-basic-example.yaml) creates an **eg-ingress** namespace with a shared Envoy Gateway. The HTTPRoute forwards **www.example.com** requests to an echo server.

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/envoy-gateway/01-basic-example.yaml

GW_IP=$(kubectl get svc -n envoy-gateway-system -l "gateway.envoyproxy.io/owning-gateway-name==eg,gateway.envoyproxy.io/owning-gateway-namespace==eg-ingress" -o jsonpath="{.items[0].status.loadBalancer['ingress'][0].ip}")

curl -v -H "Host: www.example.com" http://$GW_IP
*   Trying 104.154.202.114:80...
* Connected to 104.154.202.114 (104.154.202.114) port 80
* using HTTP/1.x
> GET / HTTP/1.1
> Host: www.example.com
> User-Agent: curl/8.14.1
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 200 OK
< content-type: application/json
< x-content-type-options: nosniff
< date: Mon, 04 Aug 2025 16:51:38 GMT
< content-length: 473
< 
{
 "path": "/",
 "host": "www.example.com",
 "method": "GET",
 "proto": "HTTP/1.1",
 "headers": {
  "Accept": [
   "*/*"
  ],
  "User-Agent": [
   "curl/8.14.1"
  ],
  "X-Envoy-External-Address": [
   "98.32.71.177"
  ],
  "X-Forwarded-For": [
   "98.32.71.177"
  ],
  "X-Forwarded-Proto": [
   "http"
  ],
  "X-Request-Id": [
   "867aeccc-c32a-47a1-a989-b4c57e4127ed"
  ]
 },
 "namespace": "eg-ingress",
 "ingress": "",
 "service": "",
 "pod": "backend-869c8646c5-q22bf"
* Connection #0 to host 104.154.202.114 left intact
}
```

# TLS Passthrough Envoy Gateway

The [02-passthrough.yaml](./02-passthrough.yaml) uses the same **eg-ingress** namespace and shared Envoy Gateway from above, with a TLSRoute to forward **passthrough.example.com** requests to another echo server with optional mTLS.

```shell
# This example uses the same basic manifest for the ns and gtw resources
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/envoy-gateway/01-basic-example.yaml
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/envoy-gateway/02-passthrough.yaml

GW_IP=$(kubectl get svc -n envoy-gateway-system -l "gateway.envoyproxy.io/owning-gateway-name==eg,gateway.envoyproxy.io/owning-gateway-namespace==eg-ingress" -o jsonpath="{.items[0].status.loadBalancer['ingress'][0].ip}")

# Server only TLS (NOTE: echo-basic app does not require mTLS)
curl -vk --resolve passthrough.example.com:6443:$GW_IP https://passthrough.example.com:6443

# Mutual TLS with client certificate from /tmp
curl -v --cacert /tmp/ca.crt --cert /tmp/tls.crt --key /tmp/tls.key \
  --resolve passthrough.example.com:6443:$GW_IP https://passthrough.example.com:6443
```

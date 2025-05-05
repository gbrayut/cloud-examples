# Anthos Service Mesh - Mutual TLS

![mutual tls example](https://cloud.google.com/static/service-mesh/docs/images/mutual-tls.svg)

Istio supports auto mTLS by default between services in the mesh. Clients and Servers using plaintext http will get converted to mTLS by the sidecar proxies. You can also use [PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/) to configure [strict mTLS](https://cloud.google.com/service-mesh/docs/security/configuring-mtls) for specific namespaces, workloads, or all services in the mesh to require mutual TLS before a server's proxy will allow an incoming request. This example shows [app-1](./app-1-permissive.yaml) as permissive (the default) and [app-2](./app-2-strict.yaml) as strict, or you can see a more detailed [microservices-demo mTLS example](https://cloud.google.com/service-mesh/docs/by-example/mtls).

```shell
# Apply app-1 and app-2 manifests
$ kubectl apply -f .
namespace/app-1 created
deployment.apps/whereami created
service/whereami created
peerauthentication.security.istio.io/app-1 created
namespace/app-2 created
deployment.apps/whereami created
service/whereami created
peerauthentication.security.istio.io/app-2 created

# Use app-1 to send a request to strict app-2 using auto mtls
$ kubectl exec -it -n app-1 deploy/whereami -- curl -vs http://whereami.app-2.svc.cluster.local
*   Trying 10.64.182.168:80...
* Connected to whereami.app-2.svc.cluster.local (10.64.182.168) port 80 (#0)
> GET / HTTP/1.1
> Host: whereami.app-2.svc.cluster.local
> User-Agent: curl/7.86.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< server: envoy
< date: Thu, 13 Apr 2023 21:26:08 GMT
< content-type: application/json
< content-length: 1183
< access-control-allow-origin: *
< x-envoy-upstream-service-time: 30
< 
{
  "cluster_name": "gke-iowa",
  "gce_instance_id": "6764094682786289931",
  "gce_service_account": "my-gke-project.svc.id.goog",
  "headers": {
    "Accept": "*/*",
    "Host": "whereami.app-2.svc.cluster.local",
    "User-Agent": "curl/7.86.0",
    "X-B3-Parentspanid": "c2ce49fd98207a6c",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "cb24001e3277e808",
    "X-B3-Traceid": "a226c6e7f6477e09c2ce49fd98207a6c",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://my-gke-project.svc.id.goog/ns/app-2/sa/default;Hash=5a58eff4cfa0451c47c66812dbb554bd13f7fb65efaba0c7dc5a55ea5b9a6fcf;Subject=\"OU=istio_v1_cloud_workload,O=Google LLC,L=Mountain View,ST=California,C=US\";URI=spiffe://my-gke-project.svc.id.goog/ns/app-1/sa/default",
    "X-Forwarded-Proto": "http",
    "X-Request-Id": "bae2b17b-5410-4b1f-ba6f-c0d9383125e6"
  },
  "host_header": "whereami.app-2.svc.cluster.local",
  "node_name": "gke-gke-iowa-default-pool-120dfdeb-j1w1",
  "pod_ip": "10.120.1.17",
  "pod_name": "whereami-69bc95f5fb-5lxwv",
  "pod_name_emoji": "📜",
  "pod_namespace": "app-2",
  "project_id": "my-gke-project",
  "timestamp": "2023-04-13T21:26:08",
  "zone": "us-central1-c"
}
* Connection #0 to host whereami.app-2.svc.cluster.local left intact

# Using app-2 to send a request to permissive app-1 would look the same
$ kubectl exec -it -n app-2 deploy/whereami -- curl -s http://whereami.app-1.svc.cluster.local
{
  "cluster_name": "gke-iowa",
  "gce_instance_id": "6764094682786289931",
  "gce_service_account": "my-gke-project.svc.id.goog",
  "headers": {
    "Accept": "*/*",
    "Host": "whereami.app-1.svc.cluster.local",
    "User-Agent": "curl/7.86.0",
    "X-B3-Parentspanid": "cf157ffb243f1fa2",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "3f81e98d83c4be8d",
    "X-B3-Traceid": "bce5725ec450a2cfcf157ffb243f1fa2",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://my-gke-project.svc.id.goog/ns/app-1/sa/default;Hash=37e886c5eedb51be7edd96a298e12c3e9c7b22f29c5aaf93bf6ea62f66d708fe;Subject=\"OU=istio_v1_cloud_workload,O=Google LLC,L=Mountain View,ST=California,C=US\";URI=spiffe://my-gke-project.svc.id.goog/ns/app-2/sa/default",
    "X-Forwarded-Proto": "http",
    "X-Request-Id": "552bf9db-accc-4607-9266-16bd425a6acb"
  },
  "host_header": "whereami.app-1.svc.cluster.local",
  "node_name": "gke-gke-iowa-default-pool-120dfdeb-j1w1",
  "pod_ip": "10.120.1.18",
  "pod_name": "whereami-69bc95f5fb-lhm2f",
  "pod_name_emoji": "🏘️",
  "pod_namespace": "app-1",
  "project_id": "my-gke-project",
  "timestamp": "2023-04-13T21:26:32",
  "zone": "us-central1-c"
}

```

A few things of note: the `server: envoy` and `x-envoy-upstream-service-time` response headers show that a local envoy sidecar proxied the client's request and server response. The `"headers"` section of the server response echos what headers were sent by the client's proxy to the destination server (beyond the original `Host:, User-Agent:, Accept:` created by curl), which in this case include the [b3 trace headers](https://cloud.google.com/service-mesh/docs/observability/accessing-traces), `X-Forwarded-Client-Cert` used for client authentication, and `X-Forwarded-Proto` indicating it was originally plaintext HTTP.

You can then attempt to access the services from outside the mesh via a pod that does not have an envoy sidecar:

```shell
# Start a test pod in istio-system namespace, which usually does not inject sidecars by default
kubectl run test -n istio-system -it --rm --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.24 --command -- /bin/bash

# Send request to permissive app-1
appuser@test:/app$ curl -vs http://whereami.app-1.svc.cluster.local
*   Trying 10.64.10.24:80...
* Connected to whereami.app-1.svc.cluster.local (10.64.10.24) port 80 (#0)
> GET / HTTP/1.1
> Host: whereami.app-1.svc.cluster.local
> User-Agent: curl/7.86.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< server: istio-envoy
< date: Thu, 13 Apr 2023 22:00:26 GMT
< content-type: application/json
< content-length: 811
< access-control-allow-origin: *
< x-envoy-upstream-service-time: 3
< x-envoy-decorator-operation: whereami.app-1.svc.cluster.local:80/*
< 
{
  "cluster_name": "gke-iowa",
  "gce_instance_id": "6764094682786289931",
  "gce_service_account": "my-gke-project.svc.id.goog",
  "headers": {
    "Accept": "*/*",
    "Host": "whereami.app-1.svc.cluster.local",
    "User-Agent": "curl/7.86.0",
    "X-B3-Sampled": "0",
    "X-B3-Spanid": "fe750e71608ddbc4",
    "X-B3-Traceid": "0e26c6ef1a176a02fe750e71608ddbc4",
    "X-Forwarded-Proto": "http",
    "X-Request-Id": "a3129853-1d86-4b81-87b4-8187b03de1ab"
  },
  "host_header": "whereami.app-1.svc.cluster.local",
  "node_name": "gke-gke-iowa-default-pool-120dfdeb-j1w1",
  "pod_ip": "10.120.1.18",
  "pod_name": "whereami-69bc95f5fb-lhm2f",
  "pod_name_emoji": "🏘️",
  "pod_namespace": "app-1",
  "project_id": "my-gke-project",
  "timestamp": "2023-04-13T22:00:26",
  "zone": "us-central1-c"
}
* Connection #0 to host whereami.app-1.svc.cluster.local left intact

# Send request to strict app-2
appuser@test:/app$ curl -vs http://whereami.app-2.svc.cluster.local
*   Trying 10.64.182.168:80...
* Connected to whereami.app-2.svc.cluster.local (10.64.182.168) port 80 (#0)
> GET / HTTP/1.1
> Host: whereami.app-2.svc.cluster.local
> User-Agent: curl/7.86.0
> Accept: */*
> 
* Recv failure: Connection reset by peer
* Closing connection 0

# Invalid request using https when Service only includes http on port 80 (no port 443)
appuser@test:/app$ curl -vs -m2 https://whereami.app-1.svc.cluster.local
*   Trying 10.64.10.24:443...
* Connection timed out after 2001 milliseconds
* Closing connection 0
```

The permissive app-1 response header has `server: istio-envoy` this time (the sidecar on the server) and `x-envoy-decorator-operation` shows the [trace span name](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/router_filter#x-envoy-decorator-operation). The second request for strict app-2 fails with `Connection reset by peer` as it will only accept request with mutal tls. And the third request times out since the Service does not have an HTTPS endpoint (`appProtocol: https`).

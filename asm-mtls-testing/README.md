# Anthos Service Mesh - Mutual TLS

Istio supports auto mTLS by default between services in the mesh. You can use [PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/) to configure [strict mTLS](https://cloud.google.com/service-mesh/docs/security/configuring-mtls) for specific namespaces, workloads, or all services in the mesh. This example shows [app-1](./app-1-permissive.yaml) as permissive and [app-2](./app-2-strict.yaml) as strict, or you can see a more detailed [microservices-demo mTLS example](https://cloud.google.com/service-mesh/docs/by-example/mtls).

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
*   Trying 10.68.189.151:80...
* Connected to whereami.app-2.svc.cluster.local (10.68.189.151) port 80 (#0)
> GET / HTTP/1.1
> Host: whereami.app-2.svc.cluster.local
> User-Agent: curl/7.83.1
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< server: envoy
< date: Tue, 11 Apr 2023 23:30:11 GMT
< content-type: application/json
< content-length: 989
< access-control-allow-origin: *
< x-envoy-upstream-service-time: 22
< 
{
  "cluster_name": "gke-oregon", 
  "headers": {
    "Accept": "*/*", 
    "Host": "whereami.app-2.svc.cluster.local", 
    "User-Agent": "curl/7.83.1", 
    "X-B3-Parentspanid": "b422a317a05420f4", 
    "X-B3-Sampled": "0", 
    "X-B3-Spanid": "09e499a7cb0a8143", 
    "X-B3-Traceid": "8ce33f6d9f1dd38fb422a317a05420f4", 
    "X-Envoy-Attempt-Count": "1", 
    "X-Forwarded-Client-Cert": "By=spiffe://my-gke-project.svc.id.goog/ns/app-2/sa/default;Hash=5ab0c6748b9dc9269d76b01d75d63707f5d0d570d14629aedd19e7bb9f605daa;Subject=\"OU=istio_v1_cloud_workload,O=Google LLC,L=Mountain View,ST=California,C=US\";URI=spiffe://my-gke-project.svc.id.goog/ns/app-1/sa/default", 
    "X-Forwarded-Proto": "http", 
    "X-Request-Id": "1f7803bc-d2e0-4cf2-9e6d-22facec5a777"
  }, 
  "host_header": "whereami.app-2.svc.cluster.local", 
  "pod_name": "whereami-7bfb479c48-bqtsd", 
  "pod_name_emoji": "🈸", 
  "project_id": "my-gke-project", 
  "timestamp": "2023-04-11T23:30:10", 
  "zone": "us-west1-a"
}
* Connection #0 to host whereami.app-2.svc.cluster.local left intact

# Use app-2 to send a request to permissive app-1 would look the same
$ kubectl exec -it -n app-2 deploy/whereami -- curl -s http://whereami.app-1.svc.cluster.local
{
  "cluster_name": "gke-oregon", 
  "headers": {
    "Accept": "*/*", 
    "Host": "whereami.app-1.svc.cluster.local", 
    "User-Agent": "curl/7.83.1", 
    "X-B3-Parentspanid": "c116358b6950fb25", 
    "X-B3-Sampled": "0", 
    "X-B3-Spanid": "3be65644e78da6d5", 
    "X-B3-Traceid": "65f64b1aea572969c116358b6950fb25", 
    "X-Envoy-Attempt-Count": "1", 
    "X-Forwarded-Client-Cert": "By=spiffe://my-gke-project.svc.id.goog/ns/app-1/sa/default;Hash=18065a394c9ce04110fdccc19e2a4a20d0e9c6240054ca57577a3db5dee37662;Subject=\"OU=istio_v1_cloud_workload,O=Google LLC,L=Mountain View,ST=California,C=US\";URI=spiffe://my-gke-project.svc.id.goog/ns/app-2/sa/default", 
    "X-Forwarded-Proto": "http", 
    "X-Request-Id": "26d5d0ef-fb5d-407d-85d2-05398aae8567"
  }, 
  "host_header": "whereami.app-1.svc.cluster.local", 
  "pod_name": "whereami-7bfb479c48-mhlzs", 
  "pod_name_emoji": "🧑🏽‍❤‍🧑🏼", 
  "project_id": "my-gke-project", 
  "timestamp": "2023-04-11T23:32:46", 
  "zone": "us-west1-a"
}
```

A few things of note: the `server: envoy` and `x-envoy-upstream-service-time` response headers show that a local envoy sidecar proxied the request and response. The `"headers"` section of the response echos what headers were sent to the destination server, which in this case include the [b3 trace headers](https://cloud.google.com/service-mesh/docs/observability/accessing-traces), `X-Forwarded-Client-Cert` used for client authentication, and `X-Forwarded-Proto` indicating it was originally plaintext HTTP.

You can then attempt to access the services from outside the mesh via a pod that does not have an envoy sidecar:

```shell
# Start a test pod in istio-system namespace, which usually does not inject sidecars by default
kubectl run test -n istio-system -it --rm --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.9 --command -- /bin/bash

# Send request to permissive app-1
appuser@test:/app$ curl -vs http://whereami.app-1.svc.cluster.local
*   Trying 10.68.228.128:80...
* Connected to whereami.app-1.svc.cluster.local (10.68.228.128) port 80 (#0)
> GET / HTTP/1.1
> Host: whereami.app-1.svc.cluster.local
> User-Agent: curl/7.83.1
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< server: istio-envoy
< date: Tue, 11 Apr 2023 23:46:24 GMT
< content-type: application/json
< content-length: 622
< access-control-allow-origin: *
< x-envoy-upstream-service-time: 28
< x-envoy-decorator-operation: whereami.app-1.svc.cluster.local:80/*
< 
{
  "cluster_name": "gke-oregon", 
  "headers": {
    "Accept": "*/*", 
    "Host": "whereami.app-1.svc.cluster.local", 
    "User-Agent": "curl/7.83.1", 
    "X-B3-Sampled": "0", 
    "X-B3-Spanid": "1be792b50a93d350", 
    "X-B3-Traceid": "e7eb42acb51427121be792b50a93d350", 
    "X-Forwarded-Proto": "http", 
    "X-Request-Id": "3da11076-badd-4629-8280-a0686113a470"
  }, 
  "host_header": "whereami.app-1.svc.cluster.local", 
  "pod_name": "whereami-7bfb479c48-mhlzs", 
  "pod_name_emoji": "🧑🏽‍❤‍🧑🏼", 
  "project_id": "my-gke-project", 
  "timestamp": "2023-04-11T23:46:24", 
  "zone": "us-west1-a"
}
* Connection #0 to host whereami.app-1.svc.cluster.local left intact

# Send request to strict app-2
appuser@test:/app$ curl -vs http://whereami.app-2.svc.cluster.local
*   Trying 10.68.189.151:80...
* Connected to whereami.app-2.svc.cluster.local (10.68.189.151) port 80 (#0)
> GET / HTTP/1.1
> Host: whereami.app-2.svc.cluster.local
> User-Agent: curl/7.83.1
> Accept: */*
> 
* Recv failure: Connection reset by peer
* Closing connection 0
```

The permissive app-1 response header has `server: istio-envoy` this time (the sidecar on the server) and `x-envoy-decorator-operation` shows the [trace span name](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/router_filter#x-envoy-decorator-operation). The second request for strict app-2 fails with `Connection reset by peer` as it will only accept request with mutal tls.

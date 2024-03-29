# Routing gRPC requests to GKE via Google Cloud Load Balancer

TODO: Add descriptions and comparisons for each LB type (NLB, Ingress, Gateway API Classic and Managed)

## Option 0: Deploy and verify gRPC service using NLB

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/gke-gclb-grpc/grpcbin-deploy-nlb.yaml

# Verify everything working directly using NLB from service resource
NLB_GRPCBIN=$(kubectl get svc grpcbin -n grpcbin | grep -v EXTERNAL-IP | awk '{ print $4}')
curl -v http://$NLB_GRPCBIN:8080/metrics
grpcurl -plaintext $NLB_GRPCBIN:9090 whereami.Whereami/GetPayload
grpcurl -plaintext -d '{"service":"whereami.Whereami"}' $NLB_GRPCBIN:9090 grpc.health.v1.Health/Check
grpcurl -vv -plaintext -d '{"greeting":"testing"}' $NLB_GRPCBIN:9000 hello.HelloService/SayHello
grpcurl -vv -insecure -d '{"greeting":"testing"}' $NLB_GRPCBIN:9001 hello.HelloService/SayHello
```

## Option 1: Using Istio CRDs for ASM Ingress Gateway

```shell
# Add gateway/virtualservice/destinationrule and check that envoy in gateway has expected listeners
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/gke-gclb-grpc/asm-istio-crd-grpcbin.yaml

istioctl pc listener istio-ingressgateway-78d5d78c6-d5ws8.istio-ingress
ADDRESS PORT  MATCH              DESTINATION
0.0.0.0 80    ALL                Route: http.80
0.0.0.0 443   SNI: *.example.com Route: https.443.https.shared-istio-gw.istio-ingress
0.0.0.0 8443  SNI: *.example.com Route: https.8443.https2.shared-istio-gw.istio-ingress
0.0.0.0 15021 ALL                Inline Route: /healthz/ready*
0.0.0.0 15090 ALL                Inline Route: /stats/prometheus*

# Test using NLB forwarding to istio-ingressgateway
NLB_ISTIOGW=$(kubectl get svc istio-ingressgateway -n istio-ingress | grep -v EXTERNAL-IP | awk '{ print $4}')

# http routes in virtual service: curl should work, but grpc fails if backend is tls (9001) instead of non-tls (9000)
curl -vk --resolve grpc.example.com:443:$NLB_ISTIOGW https://grpc.example.com/metrics
grpcurl -vv -insecure -authority grpc.example.com $NLB_ISTIOGW:443 hello.HelloService.SayHello

# tls passthrough listener fails for curl (whereami doesn't have https port) but should work for grpc (port 9001 tls)
curl -vk --resolve whereami.example.com:8443:$NLB_ISTIOGW https://whereami.example.com:8443/metrics
grpcurl -vv -insecure -authority grpc.example.com $NLB_ISTIOGW:8443 hello.HelloService.SayHello


# For troubleshooting you can increase the log level (in istio gateway or service sidecar) and then tail the logs
istioctl proxy-config log istio-ingressgateway-78d5d78c6-d5ws8.istio-ingress --level debug
kubectl logs -n istio-ingress deploy/istio-ingressgateway -c istio-proxy -f
kubectl logs -n grpcbin deploy/grpcbin -c istio-proxy -f
```

## Option 2: GKE Ingress Controller
NOTE: GKE Ingress Controller is feature frozen. Gateway API is now recommended approach.

TODO: add details. See [grpcbin-example-ingress.yaml](./grpcbin-example-ingress.yaml)

## Option 3: GKE Gateway Classic ALB gke-l7-gxlb

TODO: add details. See [grpcbin-gatewayapi-classic.yaml](./grpcbin-gatewayapi-classic.yaml)

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/gke-gclb-grpc/grpcbin-gatewayapi-classic.yaml

# Verify everything working directly using NLB from service resource
ALB_GRPCBIN=$(kubectl get gtw grpcbin-lb -n grpcbin -o=jsonpath='{.status.addresses[0].value}')
# show prometheus metrics from grpcbin port 8080 via grpcbin-route match rule
curl -vk --resolve grpc.example.com:443:$ALB_GRPCBIN https://grpc.example.com:443/metrics
# validate gRPC to backend works (check https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers or cloud logging for any errors)
grpcurl -vv -insecure -authority grpc.example.com $ALB_GRPCBIN:443 hello.HelloService.SayHello
```

## Option 4: GKE Gateway Managed ALB gke-l7-global-external-managed  

TODO: add details. See [grpcbin-gatewayapi-managed.yaml](./grpcbin-gatewayapi-managed.yaml)

## Option 5: Using Service Mesh Cloud Gateway (asm-l7-gxlb composite gateway)
NOTE: Good for quick testing, but still stuck in preview with no ETA for GA

[asm-l7-gxlb](https://cloud.google.com/service-mesh/docs/managed/service-mesh-cloud-gateway)

Uses Classic gke-l7-gxlb and then an istio gateway-api resource for managing the envoy deployment

Also the asm-gw-istio-shared-asm-cloud-gw deployment of envoy doesn't have an HPA or PDB

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/gke-gclb-grpc/asm-l7-gxlb.yaml

kubectl get gateway,svc,pod -n istio-ingress
NAME                                                                 CLASS         ADDRESS                                                                PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/asm-gw-gke-shared-asm-cloud-gw     gke-l7-gxlb   35.227.253.211                                                         True         2m34s
gateway.gateway.networking.k8s.io/asm-gw-istio-shared-asm-cloud-gw   istio         asm-gw-istio-shared-asm-cloud-gw.istio-ingress.svc.cluster.local:443   Unknown      2m35s
gateway.gateway.networking.k8s.io/shared-asm-cloud-gw                asm-l7-gxlb                                                                          Unknown      2m35s

NAME                                       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
service/asm-gw-istio-shared-asm-cloud-gw   ClusterIP   10.64.130.64   <none>        15021/TCP,443/TCP   2m35s

NAME                                                   READY   STATUS    RESTARTS   AGE
pod/asm-gw-istio-shared-asm-cloud-gw-996d89f74-9zf5t   1/1     Running   0          2m34s


istioctl pc listener asm-gw-istio-shared-asm-cloud-gw-996d89f74-wk5j9.istio-ingress
ADDRESS PORT  MATCH DESTINATION
0.0.0.0 443   ALL   Route: https.443.default.asm-gw-istio-shared-asm-cloud-gw-istio-autogenerated-k8s-gateway-https.istio-ingress
0.0.0.0 15021 ALL   Inline Route: /healthz/ready*
0.0.0.0 15090 ALL   Inline Route: /stats/prometheus*

# Test using gke-l7-gxlb forwarding to istio gateway class
kubectl wait --timeout=600s -n istio-ingress --for=condition=programmed gateways.gateway.networking.k8s.io asm-gw-gke-shared-asm-cloud-gw
ASM_GW_GSLB=$(kubectl get gateway asm-gw-gke-shared-asm-cloud-gw -n istio-ingress -o=jsonpath='{.status.addresses[0].value}')

# http routes in virtual service: curl should work, but grpc fails if backend is tls (9001) instead of non-tls (9000)
curl -vk --resolve grpc.example.com:443:$ASM_GW_GSLB https://grpc.example.com/metrics
grpcurl -vv -insecure -authority grpc.example.com $ASM_GW_GSLB:443 hello.HelloService.SayHello

# tls passthrough listener fails for curl (whereami doesn't have https port) but should work for grpc (port 9001 tls)
curl -vk --resolve whereami.example.com:8443:$NLB_ISTIOGW https://whereami.example.com:8443/metrics
grpcurl -vv -insecure -authority grpc.example.com $NLB_ISTIOGW:8443 hello.HelloService.SayHello


# For troubleshooting you can increase the log level (in istio gateway or service sidecar) and then tail the logs
istioctl proxy-config log istio-ingressgateway-78d5d78c6-d5ws8.istio-ingress --level debug
kubectl logs -n istio-ingress deploy/istio-ingressgateway -c istio-proxy -f
kubectl logs -n grpcbin deploy/grpcbin -c istio-proxy -f
```

# Misc notes or references

* https://github.com/grpc/grpc/blob/master/doc/health-checking.md
* https://chromium.googlesource.com/external/github.com/grpc/grpc/+/HEAD/doc/PROTOCOL-HTTP2.md
* https://protobuf.dev/programming-guides/encoding/

```
# This doesn't work... wireshark seems to think there is an issue with body or header frames in HTTP2
printf '\x0a\x07test123' | curl -kv --http2-prior-knowledge -X POST --data-binary @- -H "Content-Type:application/grpc" http://$NLB_GRPCBIN:9000/hello.HelloService/SayHello
```

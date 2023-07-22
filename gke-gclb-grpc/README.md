# Routing gRPC requests to GKE via Google Cloud Load Balancer

TODO: Add descriptions and comparisons for each LB type (NLB, Ingress, Gateway API Classic and Managed)

```shell
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/gke-gclb-grpc/grpcbin-deploy-nlb.yaml

# Verify everything working directly using NLB from service resource
NLB_GRPCBIN=$(kubectl get svc grpcbin -n grpcbin | grep -v EXTERNAL-IP | awk '{ print $4}')
curl -v https://$NLB_GRPCBIN:8080/metrics
grpcurl -plaintext $NLB_GRPCBIN:9090 whereami.Whereami.GetPayload
grpcurl -vv -insecure  $NLB_GRPCBIN:9001 hello.HelloService.SayHello

# Add gateway/virtualservice/destinationrule and check that envoy in gateway has expected listeners
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/gke-gclb-grpc/asm-grpcbin.yaml

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

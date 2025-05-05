# Nginx - Mutual TLS and istio-ingressgateway


```shell
# Run these commands to create istio-ingress namespace and resources (see asm-ingressgateway-classic)
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/base-ingressgateway.yaml

# Also create Internal NLB with global access so TLS can be terminated via ASM
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/svc-nlb-internal.yaml

# Then apply Istio resources for gateway, virtual service, and destination rule
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-ingressgateway-classic/istio-gw-virtualservice.yaml

# two copies of the whereami sample app:
#   app-1 permissive mTLS with VS+DR using locality loadbalancing and primary/secondary subsets
#   app-2 strict mTLS with default mesh settings (no VS/DR) that can be used as an in-mesh test app
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-1-permissive.yaml
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-2-strict.yaml


# Verify VirtualService route matches are working https://github.com/gbrayut/cloud-examples/blob/d3d3913fdc66f1fc725aaac1442f84c62c301f12/asm-ingressgateway-classic/istio-gw-virtualservice.yaml#L37-L63
NLB_IG=$(kubectl get svc -n istio-ingress istio-ingressgateway -o jsonpath="{.status.loadBalancer['ingress'][0].ip}")
curl -v -H "Host: anywhere.example.com" http://$NLB_IG/ | jq            # Returns 50/50 weighted app-1 and app-2
curl -v -H "Host: anywhere.example.com" http://$NLB_IG/app-1 | jq       # Always returns app-1
curl -v -H "Host: anywhere.example.com" http://$NLB_IG/app-2 | jq       # Always returns app-2
curl -v -H "Host: app-1.example.com"    http://$NLB_IG/ | jq            # Always returns app-1


NLB_NGINX=$(kubectl get svc -n nginx nginx -o jsonpath="{.status.loadBalancer['ingress'][0].ip}")
curl -v http://$NLB_NGINX/

$ curl -v http://$NLB_NGINX/app-1
*   Trying 34.83.80.39:80...
* Connected to 34.83.80.39 (34.83.80.39) port 80
> GET /app-1 HTTP/1.1
> Host: 34.83.80.39
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 426 Upgrade Required
< Server: nginx/1.27.0
< Date: Tue, 04 Jun 2024 22:05:17 GMT
< Content-Length: 0
< Connection: keep-alive
< 
* Connection #0 to host 34.83.80.39 left intact

gregbray@gregbray ~/code/github/cloud-examples on branch main #72 !14015 :D
$ curl -v http://$NLB_NGINX/app-2
*   Trying 34.83.80.39:80...
* Connected to 34.83.80.39 (34.83.80.39) port 80
> GET /app-2 HTTP/1.1
> Host: 34.83.80.39
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 502 Bad Gateway
< Server: nginx/1.27.0
< Date: Tue, 04 Jun 2024 22:05:24 GMT
< Content-Type: text/html
< Content-Length: 157
< Connection: keep-alive
< 
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>nginx/1.27.0</center>
</body>
</html>



istioctl proxy-config log nginx-68975c57df-mqwth.nginx --level debug




Changing svc appProtocol: tcp also fixes the issue but loses all http level metrics/observability


```
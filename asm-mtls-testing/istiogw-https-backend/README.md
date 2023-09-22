# Anthos Service Mesh - Mutual TLS to HTTPS Backends

![mutual tls example](https://istio.io/latest/docs/ops/configuration/traffic-management/tls-configuration/sidecar-connections.svg)

Most Istio deployments will use auto mTLS (sidecar-to-sidecar) with http backend services and http client requests (pod-to-pod inside the mesh). Services that require using their own TLS certificates or https client requests may require [specific settings](https://istio.io/latest/docs/ops/configuration/traffic-management/tls-configuration/) for istio-ingressgateway routing, pod-to-pod, or direct NLB to backend requests. Incorrect configuration can result in strange error messages, and there are also some known issues for specific types of requests.

The manifests in this example use the [caddy webserver](https://caddyserver.com/) for testing http and https (with sni) backends, with or without the [excludeInboundPorts](https://istio.io/latest/docs/reference/config/annotations/#:~:text=excludeInboundPorts) annotation. The port exclusion option is often used for protocol based opt-out, but in most cases there should be a way to configure client and server sidecars so that the requests are handled correctly.

```shell
# Configure GKE with ASM, then deploy test workload
# to verify sidecar injection is working
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-1-permissive.yaml
kubectl get all -n app-1

# Configure caddy backend for http/https testing
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-mtls-testing/istiogw-https-backend/01-caddy-backend.yaml

# Configure istio-ingressgateway with an external NLB and specific appProtocols
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-ingressgateway-classic/base-ingressgateway.yaml
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-mtls-testing/istiogw-https-backend/02-gw-svc-vs-dr.yaml

# Known ALPN issue for tls mode SIMPLE: https://github.com/istio/istio/issues/40680
# Fixed in Istio 1.19, but until then there is a workaround using PeerAuthentication
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-mtls-testing/istiogw-https-backend/03-fix-istio-ALPN-issue.yaml
```

## Testing backend and istio-ingressgateway

For complex ingress paths it is always best to test backends directly and then continue adding layers (Istio gateway, GCLB, CDN, etc). You can either create an NLB to directly expose the backend workload, use kubectl port forwarding, or for VPC Native clusters try testing directly against pod IP:TARGETPORT endpoints.

```shell
# Find endpoint for testing, then use curl to force specific DNS and SNI values:
kubectl get svc -A
IP=34.123.12.171
curl -vk --resolve example.com:443:$IP https://example.com/asdf
curl -vk --resolve example.com:19443:$IP https://example.com:19443/asdf
# Check SNI and certificate settings ussing openssl
echo GET "/" | openssl s_client -servername caddy.example.com -connect $IP:19443 -showcerts | openssl x509 -noout -text | grep DNS:
# -servername controls sni, and caddy doesn't work using IPs as SNI hostname

# Enable envoy debug logs for specific components or all components:
istioctl proxy-config log caddy-bbd864487-q7vk8.caddy  --level http:debug,client:debug,upstream:debug,filter:debug
istioctl proxy-config log caddy-bbd864487-q7vk8.caddy  --level debug

# View caddy or envoy sidecar logs:
kubectl logs -n caddy deploy/caddy | less -RS
kubectl logs -n caddy deploy/caddy -c istio-proxy | less -S

# If caddy has a valid cert but invalid host header (wrong port) it responds with a 200 0-length body
# If caddy tries to get a cert using ip address as fqdn it will show error in logs and have curl error:
#    curl: (35) error:14094438:SSL routines:ssl3_read_bytes:tlsv1 alert internal error
```

Once the backend is confirmed to work as expected, you can move on to testing other routing like pod-to-pod using whereami deployment as an in-mesh client:

```shell
kubectl exec -it -n app-1 deploy/whereami -- /bin/bash
# Testing using http, http-excluded, or https should all work as long as SNI is valid for Caddyfile
appuser@whereami-8f79b96c5-88n67:/app$ curl -vk http://caddy.caddy.svc.cluster.local:80
appuser@whereami-8f79b96c5-88n67:/app$ curl -vk https://caddy.caddy.svc.cluster.local:443
appuser@whereami-8f79b96c5-88n67:/app$ curl -vk http://caddy.caddy.svc.cluster.local:19080

# Testing using https-excluded port only works for http client requests 
appuser@whereami-8f79b96c5-88n67:/app$ curl -vk http://caddy.caddy.svc.cluster.local:19443
# If you try using https client (curl https://...) that will result in an error like
# curl: (35) error:1408F10B:SSL routines:ssl3_get_record:wrong version number.
# unless you create a DestinationRule tls mode SIMPLE
```

Then for testing istio-ingressgateway, again use either an NLB or port forwarding to the gateway deployment:

```shell
IP=37.123.100.10
# Simple test using whereami http backend. The same results would be expected when
# using :80:$IP and http://... URL (true for all Istio gw testing if http listener enabled)
curl -vk --resolve example.com:443:$IP https://example.com/app-1
# Testing http and http-excluded on caddy backend.
curl -vk --resolve example.com:443:$IP https://example.com/c80
curl -vk --resolve example.com:443:$IP https://example.com/c19080
# Testing https and https-excluded on caddy backend.
curl -vk --resolve example.com:443:$IP https://example.com/c443
curl -vk --resolve example.com:443:$IP https://example.com/c19443

# If any errors, you can use the above log commands to check caddy and envoy sidecar logs
# or similar commands for enabling debug logs on istio-ingressgateway envoy instance
istioctl proxy-config log deploy/istio-ingressgateway.istio-ingress  --level http:debug,client:debug,upstream:debug,filter:debug
kubectl logs -n istio-ingress deploy/istio-ingressgateway | less -S

# You can also use istioctl to check the mesh configuration for all settings on
# a specific envoy instance or filter to a specific VirtualService (cluster):
istioctl proxy-config all deploy/istio-ingressgateway.istio-ingress
istioctl pc cluster deploy/istio-ingressgateway.istio-ingress --fqdn caddy.caddy.svc.cluster.local -o yaml
```

## More Notes

I not sure if/when `insecureSkipVerify: true` is required as it seems to work fine even for self signed certs when disabled.

```
# If you see this when testing NLB to istio-ingressgateway it may be a gateway cert issue (Like missing secrets in istio-ingress namespace)
* ALPN: offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* Recv failure: Connection reset by peer
* OpenSSL SSL_connect: Connection reset by peer in connection to example.com:443
* Closing connection 0
curl: (35) Recv failure: Connection reset by peer

# If you see this when using https:// to access a mesh service, try http:// instead (or changing tls mode in destination rule)
* ALPN: offers http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* error:1408F10B:SSL routines:ssl3_get_record:wrong version number
* Closing connection 0
curl: (35) error:1408F10B:SSL routines:ssl3_get_record:wrong version number

# If you see this for istio-ingressgateway forwarding to https service, use tls mode SIMPLE instead of ISTIO_MUTUAL
< HTTP/2 503
< content-length: 218
< content-type: text/plain
< date: Fri, 22 Sep 2023 20:34:41 GMT
< server: istio-envoy
<
* Connection #0 to host example.com left intact
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: connection failure, transport failure reason: TLS error: 268435581:SSL routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED

# Caddy doesn't support generating certificates for an IP address based SNI. You would also see errors in the caddy logs.
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: connection failure, transport failure reason: TLS error: 268436536:SSL routines:OPENSSL_internal:TLSV1_ALERT_INTERNAL_ERROR
```

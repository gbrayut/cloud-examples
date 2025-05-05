exit # not that kind of script

# This will describe how to configure Cross-Origin Resource Sharing (CORS) using GKE Gateway API and Istio Ingress Gateway
# GKE Gateway does not yet support CORS at the edge LB, so instead use gateway api to provision the GCLB but configure the 
# headers in istio-ingressgateway using classic istio APIs (gw and virtualservice)

# This assumes that you start with a test GKE cluster configured for Istio service mesh

# Create backend with no cors support https://github.com/stefanprodan/podinfo
kubectl create ns podinfo
kubectl label namespace podinfo istio-injection=enabled
kubectl apply -n podinfo -k github.com/stefanprodan/podinfo/kustomize

# Create backend deployments with native cors (whereami allows all origins/methods)
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/main/asm-mtls-testing/app-2-strict.yaml

# Create envoy deployment for istio-ingressgateway (see cloud-examples/asm-ingressgateway-classic)
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-ingressgateway-classic/base-ingressgateway.yaml
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-ingressgateway-classic/svc-clusterip.yaml

# Configure ingressgateway using classic istio apis (see cors section for more details)
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-ingressgateway-classic/istio-gw-virtualservice-cors.yaml

# At this point you could do a simple (non-cors) test inside the cluster using:
kubectl run test -n istio-system --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.24
kubectl exec -it test -n istio-system -- /bin/bash
curl -H "Host: anywhere.example.com" -v http://ingressgateway.istio-ingress.svc.cluster.local
# then exit and delete the bare pod: kubectl delete pod -n istio-system test

# Use GKE Gateway API to configure L7 GCLB for access outside the cluster (see cloud-examples/asm-ingressgateway-httproute)
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-ingressgateway-httproute/asm-l7-global-external.yaml
# L7 would be best if you plan on using Cloud Armor, but does require configuring TLS certificates for tls termination at the edge
# Can still configure istio-ingressgateway to also use HTTPS instead of HTTP, but that requires creating tls secrets inside the istio-ingress namespace
# L4 LB could be used via svc-nlb-internal.yaml (no L4 GKE Gateway API support yet) if you want TLS terminated by istio-ingressgateway or use advanced mTLS features
# Or temporarily changing the service/ingressgateway type to LoadBalancer can help if you want to test directly against the Envoy deployment (bypass GCLB)



# Check GCLB status in console at https://console.cloud.google.com/kubernetes/gateways
# Check GCLB backend health status at https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers
# After 5-10 minutes you should be able to test using the GCLB IP Address:
GCLBIP=$(kubectl get gateway -n istio-ingress asm-gw-lb -o jsonpath="{.status.addresses[0].value}")
curl -v -H "Host: anywhere.example.com" http://$GCLBIP      # using anywhere-vs in istio-ingress namespace
curl -v -H "Host: podinfo.example.com"  http://$GCLBIP      # using podinfo-vs in podinfo namespace
curl -kv --resolve anywhere.example.com:443:$GCLBIP https://anywhere.example.com/app-2/headers  # routes to app-2/whereami

# Other test for cors validation (presense of access-control-allow-origin in response headers means origin is allowed)
curl -sI -H "Host: podinfo.example.com" -H "Origin: http://podinfo.example.com" http://$GCLBIP      # podinfo-vs only allows this domain (http/https)
curl -sI -H "Host: anywhere.example.com" -H "Origin: http://podinfo.example.com" http://$GCLBIP     # anywhere-vs should allow *.example.com/net/org/edu
curl -sI -H "Host: anywhere.example.com" -H "Origin: http://another.domain.com" http://$GCLBIP/         # This should not include access-control-allow-origin in response headers
curl -sI -H "Host: anywhere.example.com" -H "Origin: http://another.domain.com" http://$GCLBIP/app-2/   # whereami should include it since the app allows cors for all domains/methods
curl -ksv --resolve anywhere.example.com:443:$GCLBIP https://anywhere.example.com/headers               # can also test using https and use /headers or /app-2/headers to echo back request headers

# More complete simulation of prefetch check of cors:
curl -ksI --resolve anywhere.example.com:443:$GCLBIP \
  -H "Origin: http://www.example.com" \
  -H "Access-Control-Request-Method: GET" \
  -X OPTIONS https://anywhere.example.com/healthz

HTTP/2 200 
access-control-allow-origin: http://www.example.com
access-control-allow-methods: GET,OPTIONS
access-control-allow-headers: X-Requested-With
access-control-max-age: 7200
date: Sat, 17 Feb 2024 03:31:04 GMT
server: istio-envoy
content-length: 0
via: 1.1 google
alt-svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000




# The GKE/Gateway resources should look something like this:
$ kubectl get pods,svc,gtw,httproute -A | grep -vE "kube-system|gke-mcs"
NAMESPACE       NAME                                                          READY   STATUS    RESTARTS   AGE
app-2           pod/whereami-8f79b96c5-vfpzx                                  2/2     Running   0          45m
istio-ingress   pod/istio-ingressgateway-f655c454-kwpjf                       1/1     Running   0          45m
istio-ingress   pod/istio-ingressgateway-f655c454-lb67z                       1/1     Running   0          45m
istio-ingress   pod/istio-ingressgateway-f655c454-xcls8                       1/1     Running   0          45m
podinfo         pod/podinfo-664f9748d8-cb2lm                                  2/2     Running   0          45m
podinfo         pod/podinfo-664f9748d8-ngm7b                                  2/2     Running   0          45m

NAMESPACE       NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                    AGE
app-2           service/whereami               ClusterIP   10.64.204.155   <none>        80/TCP                     45m
default         service/kubernetes             ClusterIP   10.64.0.1       <none>        443/TCP                    68m
istio-ingress   service/ingressgateway         ClusterIP   10.64.102.198   <none>        15021/TCP,80/TCP,443/TCP   45m
podinfo         service/podinfo                ClusterIP   10.64.123.74    <none>        9898/TCP,9999/TCP          45m

NAMESPACE       NAME                                          CLASS                            ADDRESS        PROGRAMMED   AGE
istio-ingress   gateway.gateway.networking.k8s.io/asm-gw-lb   gke-l7-global-external-managed   34.149.70.30   True         40m

NAMESPACE       NAME                                               HOSTNAMES           AGE
istio-ingress   httproute.gateway.networking.k8s.io/asm-gw-route   ["*.example.com"]   40m

# The Istio Gateway/VirtualService resources should look something like this:
$ kubectl get gw,virtualservice -n istio-ingress
NAME                                          AGE
gateway.networking.istio.io/shared-istio-gw   5m23s

NAME                                             GATEWAYS              HOSTS                      AGE
virtualservice.networking.istio.io/anywhere-vs   ["shared-istio-gw"]   ["anywhere.example.com"]   5m23s



# TODO: fix end-to-end http2 testing. appProtocol http2 requires tls backend, podinfo uses plaintext http2
# For end-to-end http2 testing it is best to use a simple test server like https://github.com/stefanprodan/podinfo
# This will create a "bare-pod" deployment with istio sidecar injection using istio-ingress namespace
kubectl run podinfo -n istio-ingress --image=stefanprodan/podinfo \
  --port 8080 --expose -- ./podinfo --h2c --level debug --port 8080
# Change service port to use appProtocol http2 so service mesh knows its an http2 backend (requires tls listener inside pod)
kubectl patch svc -n istio-ingress podinfo -p '{"spec":{"ports":[{"port": 8080, "appProtocol": "http2"}]}}' --type=merge
# Tail logs on bare pod and send requests thru GCLB using test header (must enable http2 testing section in asm-l7-global-external.yaml first)
kubectl logs -n istio-ingress podinfo -f
curl $ARGS --resolve anywhere.example.com:443:$GCLBIP -H "test: true" https://anywhere.example.com/headers
# cleanup bare pod when finished
kubectl delete -n istio-ingress pod/podinfo svc/podinfo

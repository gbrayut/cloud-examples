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
kubectl run -it test -n istio-system --image=us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.9 -- /bin/bash
curl -H "Host: anywhere.example.com" -v http://ingressgateway.istio-ingress.svc.cluster.local
# then exit and delete the bare pod: kubectl delete pod -n istio-system test

# Use GKE Gateway API to configure L7 GCLB for access outside the cluster (see cloud-examples/asm-ingressgateway-httproute)
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/asm-ingressgateway-httproute/asm-l7-global-external.yaml
# L7 would be best if you plan on using Cloud Armor, but does require configuring TLS certificates for tls termination at the edge
# Can still configure istio-ingressgateway to also use HTTPS instead of HTTP, but that requires creating tls secrets inside the istio-ingress namespace
# L4 LB could be used via svc-nlb-internal.yaml (no L4 GKE Gateway API support yet) if you want TLS terminated by istio-ingressgateway or use advanced mTLS features
# Or temporarily changing the service/ingressgateway type to LoadBalancer can help if you want to test directly against the Envoy deployment (bypass GCLB)




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
NAMESPACE       NAME                                                           READY   STATUS    RESTARTS   AGE
app-2           pod/whereami-7668f75f49-7wn5p                                  2/2     Running   0          7h14m
istio-ingress   pod/istio-ingressgateway-bd96cb85c-2lgdm                       1/1     Running   0          167m
istio-ingress   pod/istio-ingressgateway-bd96cb85c-9nqt5                       1/1     Running   0          167m
istio-ingress   pod/istio-ingressgateway-bd96cb85c-vqckp                       1/1     Running   0          167m
podinfo         pod/podinfo-85c45f85db-48pdq                                   2/2     Running   0          86m
podinfo         pod/podinfo-85c45f85db-rrgbv                                   2/2     Running   0          87m

NAMESPACE       NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                                      AGE
app-2           service/whereami               ClusterIP      10.64.39.196    <none>         80/TCP                                       7h14m
istio-ingress   service/ingressgateway         LoadBalancer   10.64.51.240    35.226.91.75   15021:32213/TCP,80:30371/TCP,443:30731/TCP   6h23m
podinfo         service/podinfo                ClusterIP      10.64.180.70    <none>         9898/TCP,9999/TCP                            87m

NAMESPACE       NAME                                          CLASS                            ADDRESS         PROGRAMMED   AGE
istio-ingress   gateway.gateway.networking.k8s.io/asm-gw-lb   gke-l7-global-external-managed   34.128.145.21   True         6h43m

NAMESPACE       NAME                                               HOSTNAMES           AGE
istio-ingress   httproute.gateway.networking.k8s.io/asm-gw-route   ["*.example.com"]   6h43m


# The Istio Gateway/VirtualService resources should look something like this:
$ kubectl get gw,virtualservice -n istio-ingress
NAME                                          AGE
gateway.networking.istio.io/shared-istio-gw   6h28m

NAME                                             GATEWAYS              HOSTS                      AGE
virtualservice.networking.istio.io/anywhere-vs   ["shared-istio-gw"]   ["anywhere.example.com"]   6h28m




# For end-to-end http2 testing it is best to use a simple test server like https://github.com/stefanprodan/podinfo
# This will create a "bare-pod" deployment with istio sidecar injection using istio-ingress namespace
kubectl run podinfo -n istio-ingress --image=stefanprodan/podinfo \
  --port 8080 --expose -- ./podinfo --h2c --level debug --port 8080
# Change service port to use appProtocol http2 so service mesh knows its an http2 backend
kubectl patch svc -n istio-ingress podinfo -p '{"spec":{"ports":[{"port": 8080, "appProtocol": "http2"}]}}' --type=merge
# Tail logs on bare pod and send requests thru GCLB using test header (must enable section in istio-gw-virtualservice.yaml first)
kubectl logs -n istio-ingress podinfo -f
curl $ARGS --resolve anywhere.example.com:443:$GCLBIP -H "test: true" https://anywhere.example.com/headers
# cleanup bare pod when finished
kubectl delete -n istio-ingress pod/podinfo svc/podinfo

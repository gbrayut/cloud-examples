# GKE Gateway with Frontend mTLS Validation

For full details see https://docs.cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway#configure-frontend-mtls and for mTLS specific details including the custom GCLB variables supported see https://docs.cloud.google.com/load-balancing/docs/mtls

## Testing Global External ALB

The [global-alb-frontend-mtls.yaml](./global-alb-frontend-mtls.yaml) example shows a GKE Gateway using mTLS

```shell
PROJECT_ID=gregbray-testing

# Create test-gclb namespace with whereami target deployment
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/base-whereami.yaml

# Create configmap for mtls validation using public certificate used to issue client certs
# This is referenced in the gateway.spec.tls.frontend.default section
kubectl create configmap client-issuing-ca -n test-gclb \
  --from-file=ca.crt=./certs/issuer.mtls.example.com.crt

# If you haven't used tls policies before, make sure Network Security API is enabled
gcloud services enable networksecurity.googleapis.com --project $PROJECT_ID

# Create global external LB
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/frontend-mtls/global-alb-frontend-mtls.yaml
```

It may take 10-15 minutes for the load balancer to finish programming. You can check the status in the [Cloud Console](https://console.cloud.google.com/kubernetes/gateways) or using `kubectl describe gateway ....`

```shell
# Confirm resources were created as expected
kubectl get pod,svc,gateway -n test-gclb 

# Get GCLB IP Address
ALB_IP=$(kubectl get gtw whereami-frontend-mtls -n test-gclb -o=jsonpath='{.status.addresses[0].value}')

# Test mTLS using curl
curl -sk --cert client-123.mtls.example.com.crt --key client-123.mtls.example.com.key \
  --resolve example.com:443:$ALB_IP https://example.com | jq '.headers' | tee /tmp/headers.json
{
  "Accept": "*/*",
  "Host": "example.com",
  "User-Agent": "curl/8.20.0",
  "Via": "1.1 google",
  "X-Cloud-Trace-Context": "682cbc3d80841b97ff71894d323b7313/1199248357223208368",
  "X-Forwarded-For": "98.32.71.177,136.68.173.39",
  "X-Forwarded-Proto": "https",
  "X-Mtls-Cert-Chain": "...omitted...",
  "X-Mtls-Cert-Leaf": "...omitted...",
  "X-Mtls-Details": "present:true verified:true error:",
  "X-Mtls-Fingerprint": "b3sFlNlCkzlL0VvbiwqjTTFisd5bssdayLSSwx18AuI",
  "X-Mtls-Sans-Dns": "Y2xpZW50LTEyMy5tdGxzLmV4YW1wbGUuY29t",
  "X-Mtls-Serial-Number": "00:9a:24:3d:49:a2:2c:b6:64:e0:b4:88:aa:27:6c:b1:8b",
  "X-Mtls-Subject": "MCYxJDAiBgNVBAMTG2NsaWVudC0xMjMubXRscy5leGFtcGxlLmNvbQ=="
}

# Check thumbprint on local client cert
openssl x509 -in client-123.mtls.example.com.crt -noout -fingerprint -sha256
sha256 Fingerprint=6F:7B:05:94:D9:42:93:39:4B:D1:5B:DB:8B:0A:A3:4D:31:62:B1:DE:5B:B2:C7:5A:C8:B4:92:C3:1D:7C:02:E2

# Verify X-Mtls-Fingerprint header matches
jq -r '."X-Mtls-Fingerprint"' /tmp/headers.json | base64 -d | od -An -v -tx1
 6f 7b 05 94 d9 42 93 39 4b d1 5b db 8b 0a a3 4d
 31 62 b1 de 5b b2 c7 5a c8 b4 92 c3 1d 7c 02 e2

# Verify cert DNS header matches
jq -r '."X-Mtls-Sans-Dns"|@base64d' /tmp/headers.json
client-123.mtls.example.com

# Verify cert Subject header matches
jq -r '."X-Mtls-Subject"' /tmp/headers.json | base64 -d | openssl asn1parse -inform DER
    0:d=0  hl=2 l=  38 cons: SEQUENCE          
    2:d=1  hl=2 l=  36 cons: SET               
    4:d=2  hl=2 l=  34 cons: SEQUENCE          
    6:d=3  hl=2 l=   3 prim: OBJECT            :commonName
   11:d=3  hl=2 l=  27 prim: PRINTABLESTRING   :client-123.mtls.example.com

# Verify Leaf and Chain certificates. See https://docs.cloud.google.com/load-balancing/docs/mtls#parse-custom-header-values
jq -r '."X-Mtls-Cert-Leaf"|split(":")[1]' /tmp/headers.json | base64 -d | openssl x509 -inform DER -text -noout
jq -r '."X-Mtls-Cert-Chain"|split(":")[1]' /tmp/headers.json | base64 -d | openssl x509 -inform DER -text -noout
```

## Testing Regional External/Internal LB

The [regional-alb-frontend-mtls.yaml](./regional-alb-frontend-mtls.yaml) and [regional-ilb-frontend-mtls.yaml](./regional-ilb-frontend-mtls.yaml) examples shows regional GKE Gateways using mTLS

```shell
# Create proxy subnet for Regional GCLB (required if one does not already exist):
gcloud compute networks subnets create gclb-proxy-iowa --project $PROJECT_ID \
  --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --region=us-central1 \
  --network "projects/$PROJECT_ID/global/networks/my-gke-vpc" \
  --range=10.210.2.0/23

# Create regional external gateway with mtls
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/frontend-mtls/regional-alb-frontend-mtls.yaml

# Create regional internal gateway with mtls
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/frontend-mtls/regional-ilb-frontend-mtls.yaml

# Test gke-l7-regional-external-managed
RLB_IP=$(kubectl get gtw whereami-frontend-mtls-uc1 -n test-gclb -o=jsonpath='{.status.addresses[0].value}')
curl -sk --cert client-123.mtls.example.com.crt --key client-123.mtls.example.com.key --resolve example.com:443:$RLB_IP https://example.com | jq '.headers' | tee /tmp/headers.json

# Test internal gke-l7-rilb
ILB_IP=$(kubectl get gtw whereami-frontend-mtls-uc1-ilb -n test-gclb -o=jsonpath='{.status.addresses[0].value}')
curl -sk --cert client-123.mtls.example.com.crt --key client-123.mtls.example.com.key --resolve example.com:443:$ILB_IP https://example.com | jq '.headers' | tee /tmp/headers.json
```

# Using SPIFFE for managing ghostunnel certificates

So I'm pretty sure this wont work... as GKE generates spiffe certs but doesn't include the SPIFFE Workload API needed for SPIFFE_ENDPOINT_SOCKET/--use-workload-api-addr

GKE mesh certificates https://cloud.google.com/blog/products/networking/traffic-director-integrates-with-ca-service
https://cloud.google.com/traffic-director/docs/security-overview

Identity reflection https://cloud.google.com/certificate-authority-service/docs/using-identity-reflection
REFLECTED_SPIFFE https://cloud.google.com/certificate-authority-service/docs/tutorials/using-3pi-with-reflection#issue-certificate

mount certs
https://github.com/istio/istio/issues/25153#issuecomment-661971600

```bash
# See whereami-deploy.yaml for client test pod that deploys into an namespace with sidecar istio-injection
kubectl create ns testing
kubectl label namespace testing istio-injection=enabled istio.io/rev- --overwrite
kubectl apply -f ./whereami-deploy.yaml

```
See [echoserver-testing.txt](./echoserver-testing.txt) for example output

## Other

Setup instructions https://cloud.google.com/traffic-director/docs/security-envoy-setup#enable-api
# enable apis first? below command may take 30 minutes to install gke-spiffe-node-agent daemonset
gcloud container clusters update gke-iowa --enable-mesh-certificates --project gregbray-vpc



gcloud privateca pools add-iam-policy-binding my-ca \
 --location us-central1 --project gregbray-cas \
 --role roles/privateca.auditor \
 --member="serviceAccount:service-503076227230@container-engine-robot.iam.gserviceaccount.com"
 
gcloud privateca pools add-iam-policy-binding my-ca \
  --location us-central1 --project gregbray-cas \
  --role roles/privateca.certificateManager \
  --member="serviceAccount:service-503076227230@container-engine-robot.iam.gserviceaccount.com"


kubectl apply -f ./workloadcerts.yaml
kubectl describe WorkloadCertificateConfig,TrustConfig

kubectl create ns td-mtls
kubectl label namespace td-mtls istio-injection=enabled ?? only needed if using sidecar injector, which would conflict with ASM injector

not sure what this is used by/for.
gcloud projects add-iam-policy-binding gregbray-vpc \
  --member serviceAccount:503076227230-compute@developer.gserviceaccount.com \
  --role roles/trafficdirector.client
for now try using test-sa instead

also make sure to grant ksa access to gsa


istioctl proxy-config bootstrap mesh-gateway-69f4cccf46-9s4vv.td-mtls

using spiffe csr signing
https://cloud.google.com/traffic-director/docs/security-envoy-setup#csrs_are_not_approved

ls /var/run/secrets/workload-spiffe-credentials





https://cloud.google.com/traffic-director/docs/security-envoy-setup#set-up-authz-ingress-gateway

https://cloud.google.com/traffic-director/docs/security-envoy-setup#validate-deployent
GET / HTTP/1.1
Host: 35.196.50.2
x-forwarded-client-cert: By=spiffe://PROJECT_ID.svc.id.goog/ns/K8S_NAMESPACE/sa/DEMO_SERVER_KSA;Hash=Redacted;Subject="Redacted;URI=spiffe://PROJECT_ID.svc.id.goog/ns/K8S_NAMESPACE/sa/DEMO_CLIENT_KSA
x-envoy-expected-rq-timeout-ms: 15000
user-agent: curl/7.72.0
x-forwarded-proto: https
content-length: 0
x-envoy-internal: true
x-request-id: 98bec135-6df8-4082-8edc-b2c23609295a
accept: */*
x-forwarded-for: 10.142.0.7


VM setup https://cloud.google.com/traffic-director/docs/auto-vms-options


Cert details:
ls /var/run/secrets/workload-spiffe-credentials/
ca_certificates.pem  certificates.pem  private_key.pem

openssl x509 -noout -text -in /var/run/secrets/workload-spiffe-credentials/certificates.pem
            Authority Information Access: 
                CA Issuers - URI:http://privateca-content-62e3dd84-0000-23cd-9ac8-883d24ff43e8.storage.googleapis.com/07862a6b4e18ed2a78cd/ca.crt

            X509v3 Subject Alternative Name: 
                URI:spiffe://gregbray-vpc.svc.id.goog/ns/td-mtls/sa/td-mtls-ksa
            1.3.6.1.4.1.11129.2.6.1.1: 
                0&.$f98b4aeb-7269-4b82-8c46-f52cbb91e440
            1.3.6.1.4.1.11129.2.6.1.2: 
                0...mesh-gateway-68f9c7ffb5-2tcjj
            1.3.6.1.4.1.11129.2.6.1.3: 
                0&.$0d6c1118-7501-4802-991c-169c10f9657e


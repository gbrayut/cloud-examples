# Workload Identity Federation Testing

This demonstrates how to use the default OIDC provider from a Kubernetes in Docker ([kind](https://kind.sigs.k8s.io/)) cluster to access a Google Cloud Storage bucket via Workload Identity Federation. It emulates an on-prem workload -> Google Cloud API access pattern, but usually you would use a dedicated IDP for DIY Kubernetes instead of the one built into the api server.

## Create local test cluster

First create a local cluster using https://k3d.io/ then grant [permissions](./oidc-discovery.yaml) to allow public access to OIDC discovery endpoints.

```shell
# show blank slate (no containers or credentials on server)
docker ps
gcloud auth list

# create kind cluster and re-enable anonymous auth for public OIDC discovery endpoints
# also update issuer and jwks endpoint https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection
mydomain="demo.a-z.dev" # FQDN to be used for issuer and jwks (which are optional, can instead just use static --jwk-json-path file below)
k3d cluster create test --api-port localhost:6550 \
  --k3s-arg "--kube-apiserver-arg=--anonymous-auth=true@server:*" \
  --k3s-arg "--kube-apiserver-arg=--service-account-issuer=https://$mydomain@server:*" \
  --k3s-arg "--kube-apiserver-arg=--service-account-jwks-uri=https://$mydomain/openid/v1/jwks@server:*"

# see nodes/pods of test cluster
kubectl get nodes
kubectl get pods -A

# test using gcloud container (still no credentials)
kubectl run -it --rm gcloud --image=google/cloud-sdk:slim --restart=Never
gcloud auth list

# see OIDC discovery endpoints using kubeconfig authentication and save jwks for use with --jwk-json-path if needed
kubectl get --raw /.well-known/openid-configuration | jq
kubectl get --raw /openid/v1/jwks | tee /tmp/jwks.json | jq

# see endpoints via public url with no bearer header (will fail until public access binding for OIDC is created)
curl -sk https://localhost:6550/.well-known/openid-configuration | jq
curl -sk https://localhost:6550/openid/v1/jwks | jq

# create binding for public OIDC discovery https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-issuer-discovery
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/kind-identity-federation/oidc-discovery.yaml

# using a proxy like ngrok or cloudflared tunnel you can make the discovery endpoint
# publically accesible with a valid https certificate (required for federation)
curl -s https://demo.a-z.dev/.well-known/openid-configuration | jq
curl -s https://demo.a-z.dev/openid/v1/jwks | jq
```

## Configure Google Cloud Workload Identity Federation Pool

Open https://console.cloud.google.com/iam-admin/workload-identity-pools?cloudshell=true and configure [oidc pool](https://cloud.google.com/sdk/gcloud/reference/iam/workload-identity-pools/providers/create-oidc)

Then deploy a [test pod](./gcloud-adc.yaml) and [test application](./gcs-buckets.py) to confirm access

```shell
# create a demo pool (can hold multiple identity providers)
# note: these cannot be fully deleted, only inactivated and then potentially restored later
gcloud iam workload-identity-pools create demo --project gregbray-repo \
  --location="global" \
  --description="demo wif pool for k3d cluster" \
  --display-name="demo-pool"

# add demo cluster oidc provider to the pool
# note: these also cannot be fully deleted, only inactivated and then potentially restored later
issuer="https://kubernetes.default.svc.cluster.local" # default for most kubernetes clusters, but not publically accessible
#issuer="https://demo.a-z.dev"  # matching mydomain value used above
gcloud iam workload-identity-pools providers create-oidc demo-oidc-provider --project gregbray-repo \
  --location="global" --workload-identity-pool="demo" --display-name="k3d oidc provider" \
  --description="demo d3d oidc provider" --attribute-mapping="google.subject=assertion.sub" \
  --attribute-condition="true" --issuer-uri="$issuer" \
  --allowed-audiences="https://gcp.a-z.dev,https://federation.a-z.dev" \
  --jwk-json-path="/tmp/jwks.json"

# omit the jwk-json-path parameter if the issuer endpoint is publically accessible. GCP will query /.well-known/openid-configuration
# add --disabled if you want to create the provider but require it to still be enabled via UI/CLI later

# create pod for testing (this may take a few minutes, uses the same developer image as Google Cloud Shell)
kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/main/kind-identity-federation/gcloud-adc.yaml 
kubectl exec -it -n testing gcloud-bare-pod -- /bin/bash

# inside the pod, view the ADC config file and KSA token (decode using https://jwt.io/)
grep . /var/run/secrets/tokens/k3d-ksa/*

# use gcloud to test the ADC json config and get ubermint token. If fails make sure jwks is correct on pool.
gcloud auth application-default print-access-token
# activate the ADC config file for use via gcloud commands. Also inspect http calls.
gcloud config set core/log_http_redact_token false
gcloud --log-http auth login --cred-file=${GOOGLE_APPLICATION_CREDENTIALS:-ERRMISSINGENV}
gcloud auth list
gcloud storage buckets list --project gregbray-repo   # Only works after assigning permisions (see below)

# Can also install python cloud sdk for testing
pip install google-cloud-storage
# paste contents from gcs-buckets.py to list GCS buckets (will fail due to missing permissions)

# assign permissions to byo-id principal (via cloud shell)
gcloud projects add-iam-policy-binding gregbray-repo \
  --role="roles/storage.admin" \
  --member="principal://iam.googleapis.com/projects/388410766669/locations/global/workloadIdentityPools/demo/subject/system:serviceaccount:testing:gcloud-ksa"
# more at https://cloud.google.com/iam/docs/principal-identifiers#v2
# all identities from issuer --member="principalSet://iam.googleapis.com/projects/388410766669/locations/global/workloadIdentityPools/demo/*"
```

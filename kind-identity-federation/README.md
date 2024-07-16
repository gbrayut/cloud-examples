# Workload Identity Federation Testing

This demonstrates how to use the default OIDC provider from a Kubernetes in Docker ([kind](https://kind.sigs.k8s.io/)) cluster to access a Google Cloud Storage bucket via Workload Identity Federation. It emulates an on-prem workload -> Google Cloud API access pattern, but usually you would use a dedicated IDP for DIY Kubernetes instead of the one built into the api server.

TODO: figure out how to change k3d cluster domain (for jwk issuer) or use explicit --service-account-issuer so jwks endpoint has a valid public FQDN and Google Cloud can use well-known discovery endpoints instead of a static json file.

## Create local test cluster

First create a local cluster using https://k3d.io/ then grant [permissions](./oidc-discovery.yaml) to allow public access to OIDC discovery endpoints.

```shell
# show blank slate (no containers or credentials on server)
docker ps
gcloud auth list

# create kind cluster and re-enable anonymous auth if you want to use public OIDC discovery endpoints
k3d cluster create test --api-port localhost:6550 \
  --k3s-arg --kube-apiserver-arg=--anonymous-auth=true@server:*

# see nodes/pods of test cluster
kubectl get nodes
kubectl get pods -A

# test using gcloud container (still no credentials)
kubectl run -it --rm gcloud --image=google/cloud-sdk:slim --restart=Never
gcloud auth list

# see OIDC discovery endpoints using kubeconfig authentication (and save jwks for later use)
kubectl get --raw /.well-known/openid-configuration | jq
kubectl get --raw /openid/v1/jwks | tee /tmp/jwks.json | jq

# see endpoints via public url (will fail until public access binding is created)
curl -sk https://localhost:6550/.well-known/openid-configuration | jq
curl -sk https://localhost:6550/openid/v1/jwks | jq

# create role/binding to allow public access to OIDC discovery endpoints
kubectl apply -f ./oidc-discovery.yaml

# if you use ngrok or cloudflared tunnel you can configure public endpoint
curl -sk https://demo.a-z.dev/.well-known/openid-configuration | jq
curl -sk https://demo.a-z.dev/openid/v1/jwks | jq
```

## Configure Google Cloud Workload Identity Federation Pool

Open https://console.cloud.google.com/iam-admin/workload-identity-pools?cloudshell=true and configure [oidc pool](https://cloud.google.com/sdk/gcloud/reference/iam/workload-identity-pools/providers/create-oidc)

Then deploy a [test pod](./gcloud-adc.yaml) and [test application](./gcs-buckets.py) to confirm access

```shell
# create a demo pool (can hold multiple identity providers)
gcloud iam workload-identity-pools create demo --project gregbray-repo \
  --location="global" \
  --description="demo wif pool for k3d cluster" \
  --display-name="demo-pool"

# add kind cluster oidc provider to the pool
gcloud iam workload-identity-pools providers create-oidc demo-oidc-provider \
  --location="global" --workload-identity-pool="demo" --display-name="k3d oidc provider" \
  --description="demo d3d oidc provider" --attribute-mapping="google.subject=assertion.sub" \
  --attribute-condition="true" --issuer-uri="https://kubernetes.default.svc.cluster.local" \
  --allowed-audiences="https://gcp.a-z.dev,https://federation.a-z.dev" \
  --jwk-json-path="/tmp/jwks.json"

# omit the jwk-json-path parameter if the issuer endpoint is publically accessible
# add --disabled if you want the provider created but still needs to be enabled via UI/CLI later

# create pod for testing (this may take a few minutes, uses the same developer image as Google Cloud Shell)
kubectl apply -f ./gcloud-adc.yaml 
kubectl exec -it -n testing gcloud-bare-pod -- /bin/bash

# inside the pod, view the ADC config file and KSA token (decode using https://jwt.io/)
grep . /var/run/secrets/tokens/k3d-ksa/*

# use gcloud to test the ADC json config and get ubermint token. If fails make sure jwks correct on pool.
gcloud auth application-default print-access-token

# since gcloud doesn't support using ADC for commands yet, install python cloud sdk for testing
pip install google-cloud-storage
# paste contents from gcs-buckets.py to list GCS buckets (will fail due to missing permissions)

# assign permissions to byo-id principal (via cloud shell)
gcloud projects add-iam-policy-binding gregbray-repo \
  --role="roles/storage.admin" \
  --member="principal://iam.googleapis.com/projects/388410766669/locations/global/workloadIdentityPools/demo/subject/system:serviceaccount:testing:gcloud-ksa"
# more at https://cloud.google.com/iam/docs/principal-identifiers#v2
# all identities from issuer --member="principalSet://iam.googleapis.com/projects/388410766669/locations/global/workloadIdentityPools/demo/*"
```

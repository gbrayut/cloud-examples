# Create local test cluster using https://k3d.io/
k3d cluster create test --api-port localhost:6550 --k3s-arg --kube-apiserver-arg=--anonymous-auth=true@server:*

kubectl get nodes
kubectl apply -f ./oidc-discovery.yaml

kubectl run -it --rm gcloud --image=google/cloud-sdk:slim --restart=Never

kubectl get --raw /.well-known/openid-configuration | jq
kubectl get --raw /openid/v1/jwks | jq

curl -sk https://localhost:6550/.well-known/openid-configuration | jq
curl -sk https://localhost:6550/openid/v1/jwks | jq



host.k3d.internal)


curl -sk https://demo.a-z.dev/.well-known/openid-configuration | jq
curl -sk https://demo.a-z.dev/openid/v1/jwks | jq


https://console.cloud.google.com/iam-admin/workload-identity-pools?cloudshell=true&project=gregbray-repo

# https://cloud.google.com/sdk/gcloud/reference/iam/workload-identity-pools/providers/create-oidc
gcloud iam workload-identity-pools create demo --project gregbray-repo \
  --location="global" \
  --description="demo wif pool for k3d cluster" \
  --display-name="demo-pool"

gcloud iam workload-identity-pools providers create-oidc demo-oidc-provider \
  --location="global" --workload-identity-pool="demo" --display-name="k3d oidc provider" \
  --description="demo d3d oidc provider" --disabled --attribute-mapping="google.subject=assertion.sub" \
  --attribute-condition="true" --issuer-uri="https://kubernetes.default.svc.cluster.local" \
  --allowed-audiences="https://gcp.a-z.dev,https://federation.a-z.dev" --jwk-json-path="path/to/jwk.json"

https://storage.cloud.google.com/gregbray-repo-gcs/testing.html



kubectl apply -f ./gcloud-adc.yaml 
kubectl exec -it -n testing gcloud-bare-pod -- /bin/bash

grep . /var/run/secrets/tokens/k3d-ksa/*

gcloud auth application-default print-access-token


pip install google-cloud-storage

# https://cloud.google.com/iam/docs/principal-identifiers#v2
gcloud projects add-iam-policy-binding gregbray-repo \
  --role="roles/storage.admin" \
  --member="principal://iam.googleapis.com/projects/388410766669/locations/global/workloadIdentityPools/demo/subject/system:serviceaccount:testing:gcloud-ksa"
#or for all users --member="principalSet://iam.googleapis.com/projects/388410766669/locations/global/workloadIdentityPools/demo/*" \
 


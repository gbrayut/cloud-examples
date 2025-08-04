# GKE cert-manager Overview

The OSS cert-manager project can be used to generate certificates from various [Certificate Authorities](https://cert-manager.io/docs/configuration/issuers/) using either namespaced Issuer or ClusterIssuer resources such as:

1. [cert-manager CA](https://cert-manager.io/docs/configuration/ca/) often used for self-signed demos or as the basis of DIY Private CA / Public Key Infrastructure (PKI)
1. [Google Certificate Authority Service (CAS)](https://github.com/cert-manager/google-cas-issuer) for [Google Managed Private CA / PKI](https://cloud.google.com/certificate-authority-service/docs/ca-service-overview)
1. [Google Trust Services](https://cloud.google.com/certificate-manager/docs/public-ca-tutorial) or [Let's Encrypt](https://letsencrypt.org/how-it-works/) via [acme-issuer](https://cert-manager.io/docs/configuration/acme/) for automated Server TLS certificates

OSS cert-manager and it's CA issuers are **not a Google supported project**, but you can follow the [installation instructions](https://cert-manager.io/docs/installation/) to get started via [Helm](https://helm.sh/docs/intro/install/):

```shell
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
# Install csi-driver for certificates via volumes https://cert-manager.io/docs/usage/csi/
helm install cert-manager-csi-driver jetstack/cert-manager-csi-driver \
  --namespace cert-manager \
  --wait

# View namespace resources
kubectl get all -n cert-manager
```

# Configure Certificate Authorities

This repo has a few examples of how to configure ClusterIssuers:

* [00a-ca-issuer.yaml](./00a-ca-issuer.yaml) is a self-signed demo CA issuer, which does not have any domain or issuing restrictions

* [00b-gcp-cas-issuer.yaml](./00b-gcp-cas-issuer.yaml) uses an existing Google CAS pool via GKE Workload Identity (full configuration outside the scope of this example)

* [00c-gts-acme-issuer.yaml](./00c-gts-acme-issuer.yaml) uses Google's ACME endpoint via account key secret (full configuration outside the scope of this example)

Once you have a ClusterIssuer or namespaced Issuer there are multiple ways to [issue certificates](https://cert-manager.io/docs/usage/), including using the [CSI driver](https://github.com/gbrayut/cloud-examples/blob/006cbf322037630c56e64ba49906ff81d14af079/gke-gclb-misc/envoy-gateway/02-passthrough.yaml#L77-L96) for server or mutual TLS or using [Certificate](https://cert-manager.io/docs/usage/certificate/) CRDs to generate Kubernetes Secrets.

# Sync with Remote Certificate Stores

If you need to copy certificates into other locations (AWS ACM, GCP Certificate Manager, HashiCorp Vault, etc), you can first see if the destination has native support for Kubernetes Secrets. For instance, GCP [Config Connector](https://cloud.google.com/config-connector/docs/overview) can use [CertificateManagerCertificate](https://cloud.google.com/config-connector/docs/reference/resource-docs/certificatemanager/certificatemanagercertificate) CRD with secretKeyRef to manage regional or global certificates for use by internal or external Google Cloud Load Balancers.

Another option is the OSS [cert-manager-sync](https://github.com/robertlestak/cert-manager-sync) project which extends cert-manager to sync with various remote certificate stores.

```shell
# Example of installing cert-manager-sync on GKE for GCP Certificate Manager Sync
PROJECT_ID=my-project
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

git clone git@github.com:robertlestak/cert-manager-sync.git
cd cert-manager-sync
helm upgrade --install -n cert-manager cert-manager-sync ./deploy/cert-manager-sync

# Use GKE Workload Identity and grant KSA the required permissions
POOL="principal://iam.googleapis.com/projects/$PROJECT_NUM/locations/global/workloadIdentityPools/$PROJECT_ID.svc.id.goog"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="$POOL/subject/ns/cert-manager/sa/cert-manager-sync" \
    --role=roles/certificatemanager.editor --condition=None

# View namespace resources
kubectl get all -n cert-manager
```

After the service is running, you can use annotations to configure where the TLS secrets are synced (See [gcm-sync-example.yaml](./gcm-sync-example.yaml)).

# More Examples

* OSS [Envoy Gateway](../gke-gclb-misc/envoy-gateway) for in-cluster L7 or Passthrough via Kubernetes Gateway API
* TODO: GKE Gateway example with Certificate Manager for regional/global certificates

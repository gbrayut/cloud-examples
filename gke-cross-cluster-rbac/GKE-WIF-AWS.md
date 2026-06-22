# Access AWS using Google Cloud Identities
[Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) is the recommended way for most GKE workloads to access Google Cloud or other external services. For [accessing services in AWS from GKE](https://aws.amazon.com/blogs/security/access-aws-using-a-google-cloud-platform-native-workload-identity/), WIF with Google Service Account (GSA) [impersonation](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#kubernetes-sa-to-iam) is the usual recommendation since OIDC tokens issued by **accounts.google.com** can be used directly in AWS via the preconfigured Google OIDC provider.

If you don't want to create a GSA for each workload, you can also configure [OIDC Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html) so that AWS can directly validate JSON Web Tokens (JWT) issued to Kubernetes Service Accounts and use those web identities to [assume AWS Roles](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html). However, these cluster-level tokens are not issued by accounts.google.com, which is only used for Google user and service account identities. So you will need to repeat the OIDC Provider steps in AWS for each GKE cluster or find a centralized provider that can relay/consolidate identities from different clusters into one trusted Identity Provider (IdP).

## Configure AWS OIDC Provider for GKE Cluster

You can [create an OIDC Provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html) in AWS using the console (IAM -> Identity Providers) or AWS CLI:

```shell
# GKE OIDC Issuer looks like https://container.googleapis.com/v1/projects/[PROJECT_ID]/locations/[CLUSTER_LOCATION]/clusters/[CLUSTER_NAME]
OIDC_ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)
aws iam create-open-id-connect-provider \
    --url "$OIDC_ISSUER" \
    --client-id-list sts.amazonaws.com

# You can replace sts.amazonaws.com with my-federated-oidc.example.com or whatever custom audience you 
# want to use for OIDC Federation as long at it matches what is used in the JWT issued to pods
```

## Configure AWS IAM Role and Trust Policy

You can [create a Role for OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html) in AWS using the console (IAM -> Role -> Web identity) or AWS CLI:

```shell
# AWS Account, GKE OIDC Issuer (without https://), and expected Audience
ACCOUNT="654321012345"
ISSUER="container.googleapis.com/v1/projects/gregbray-vpc/locations/us-central1/clusters/gke-iowa"
AUDIENCE="sts.amazonaws.com"  # Must match audience used when creating OIDC Provider and issuing tokens to Pod
# Subject for GKE KSA looks like: system:serviceaccount:[NAMESPACE]:[KSA_NAME]
SUBJECT="system:serviceaccount:test-aws-cli:aws-access-ksa"
cat << EOF > /tmp/trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
    "Effect": "Allow",
    "Principal": {
          "Federated": "arn:aws:iam::$ACCOUNT:oidc-provider/$ISSUER"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
          "StringEquals": {
              "$ISSUER:aud": "$AUDIENCE",
              "$ISSUER:sub": "$SUBJECT"
          }
    }
    }
  ]
}
EOF

# Create AWS role
aws iam create-role --role-name "GKEProdIowaFederatedRoleForS3Access" \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "IAM role assumed by GKE Prod Iowa cluster pods via Web Identity Federation."
# Assign AWS permissions to role
aws iam attach-role-policy \
    --role-name "GKEProdIowaFederatedRoleForS3Access" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
```

## Testing AWS AssumeRoleWithWebIdentity for GKE Based OIDC Provider
After updating the `AWS_ROLE_ARN` and `audience` values in the [02-test-gke-wif-aws.yaml](02-test-gke-wif-aws.yaml) file to match what you used above you can test if GKE -> AWS S3 access is working:

```shell
kubectl apply -f gke-cross-cluster-rbac/02-test-gke-wif-aws.yaml

kubectl exec -it -n test-aws-cli deploy/aws-cli -- /bin/bash
bash-5.2# export AWS_WEB_IDENTITY_TOKEN_FILE=/root/cfg/token
bash-5.2# export AWS_ROLE_ARN=arn:aws:iam::654321012345:role/GKEProdIowaFederatedRoleForS3Access
bash-5.2# aws s3api list-buckets
{
    "Buckets": [
        {
            "Name": "gregbray-testing",
            "CreationDate": "2026-06-17T21:26:49+00:00",
            "BucketArn": "arn:aws:s3:::gregbray-testing"
        }
    ],
    "Owner": {
        "ID": "b0e695ee46787fa7f......8525c4a9766864"
    },
    "Prefix": null
}
bash-5.2# aws sts assume-role-with-web-identity --role-arn "$AWS_ROLE_ARN" --role-session-name "gke-session" --web-identity-token "file:///$AWS_WEB_IDENTITY_TOKEN_FILE"
{
    "Credentials": {
        "AccessKeyId": "ASIAZR......XG2W",
        "SecretAccessKey": "OGP0kQm......KCXL/a3r",
        "SessionToken": "FwoGZXIvYXdzEOL//////////......NGRSAXrmaAuMeQ==",
        "Expiration": "2026-06-18T01:23:16+00:00"
    },
    "SubjectFromWebIdentityToken": "system:serviceaccount:test-aws-cli:aws-access-ksa",
    "AssumedRoleUser": {
        "AssumedRoleId": "AROAZRVSTYEHCL3EO4JVN:url-session",
        "Arn": "arn:aws:sts::654321012345:assumed-role/GKEProdIowaFederatedRoleForS3Access/gke-session"
    },
    "Provider": "arn:aws:iam::654321012345:oidc-provider/container.googleapis.com/v1/projects/gregbray-vpc/locations/us-central1/clusters/gke-iowa",
    "Audience": "sts.amazonaws.com"
}
```

## AWS AssumeRoleWithWebIdentity using Google Service Account

The above process can be a bit simpler if your workload instead impersonates a Google Service Account using the `iam.gke.io/gcp-service-account` annotation, although that will also make accessing and managing the short-lived tokens in each pod a bit more complex. In the GSA impersonation use-case you can skip creating an OIDC Provider in AWS and just create role statements like:

```shell
# Get Unique ID from https://console.cloud.google.com/iam-admin/serviceaccounts or using gcloud
UNIQUEID=$(gcloud iam service-accounts describe test-sa@gregbray-vpc.iam.gserviceaccount.com --format "value(uniqueId)")

# Update AWS role trusted entities to include GSA authorization
# From https://aws.amazon.com/blogs/security/access-aws-using-a-google-cloud-platform-native-workload-identity/#define_IAM_role
{
  "Version": "2012-10-17",
  "Statement": [
    { ... other statements like cluster-level federated oidc-provider from above ... },
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "accounts.google.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "accounts.google.com:aud": "$UNIQUEID",
          "accounts.google.com:oaud": "sts.amazonaws.com",          
          "accounts.google.com:sub": "$UNIQUEID"
        }
      }
    }
  ]
}

# Grant KSA permissions to impersonate GSA. For principal and principalset options 
# see https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
BASEID="iam.googleapis.com/projects/601234567890/locations/global/workloadIdentityPools/"
gcloud iam service-accounts add-iam-policy-binding test-sa@gregbray-vpc.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principal://$BASEID/gregbray-vpc.svc.id.goog/subject/ns/test-aws-cli/sa/aws-access-ksa"
# Legacy KSA identity format also works:
  --member="serviceAccount:gregbray-vpc.svc.id.goog[test-aws-cli/aws-access-ksa]"

# And make sure the KSA is using the iam.gke.io/gcp-service-account annotation:
kubectl patch sa -n test-aws-cli aws-access-ksa --type merge \
  -p '{"metadata":{"annotations":{"iam.gke.io/gcp-service-account": "test-sa@gregbray-vpc.iam.gserviceaccount.com"}}}'
```

Then instead of using a projected KSA token, your workloads should use [Application Default Credentials](https://docs.cloud.google.com/docs/authentication/application-default-credentials) (programmatically via Google Cloud SDK/libraries or something like `gcloud auth print-identity-token --audiences=sts.amazonaws.com`) or manually request tokens from the GKE Metadata server:

```shell
kubectl exec -it -n test-aws-cli deploy/aws-cli -- /bin/bash

# Get short-lived token directly using GKE Metadata Server
bash-5.2# curl -sH "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=sts.amazonaws.com" -o /root/gsa_token
# Validate token using tokeninfo API call
bash-5.2# curl "https://oauth2.googleapis.com/tokeninfo?id_token=$(cat /root/gsa_token)"
{
  "aud": "sts.amazonaws.com",
  "azp": "108222364016549509974",
  "email": "test-sa@gregbray-vpc.iam.gserviceaccount.com",
  "email_verified": "true",
  "exp": "1782156873",
  "iat": "1782153273",
  "iss": "https://accounts.google.com",
  "sub": "108222364016549509974",
  "alg": "RS256",
  "kid": "d12978ba4c29ef1154a34e4870c7a3a51d26df10",
  "typ": "JWT"
}

bash-5.2# export AWS_WEB_IDENTITY_TOKEN_FILE=/root/gsa_token
bash-5.2# export AWS_ROLE_ARN=arn:aws:iam::654321012345:role/GKEProdIowaFederatedRoleForS3Access
bash-5.2# aws s3api list-buckets
{
    "Buckets": [
        {
            "Name": "gregbray-testing",
            "CreationDate": "2026-06-17T21:26:49+00:00",
            "BucketArn": "arn:aws:s3:::gregbray-testing"
        }
    ],
    "Owner": {
        "ID": "b0e695ee46787fa7fd5b1075b93dc7aa9fd2e5fc96d9dca9188525c4a9766864"
    },
    "Prefix": null
}
bash-5.2# aws sts assume-role-with-web-identity --role-arn "$AWS_ROLE_ARN" --role-session-name "gsa-session" --web-identity-token "file:///$AWS_WEB_IDENTITY_TOKEN_FILE"
{
    "Credentials": {
        "AccessKeyId": "ASIAZR......ZPON",
        "SecretAccessKey": "cS2dt4/......6gAP6w",
        "SessionToken": "FwoGZXIvY......PkxS4Q0nH/VO",
        "Expiration": "2026-06-22T19:54:46+00:00"
    },
    "SubjectFromWebIdentityToken": "108222364016549509974",
    "AssumedRoleUser": {
        "AssumedRoleId": "AROAZRVSTYEHDHF65PC5F:gsa-session",
        "Arn": "arn:aws:sts::654321012345:assumed-role/GKEProdIowaFederatedRoleForS3Access/gsa-session"
    },
    "Provider": "accounts.google.com",
    "Audience": "108222364016549509974"
}

# NOTE: the gsa token and aws credentials would need to be periodically renewed as both default
# to 3600 seconds before they expire. This usually is done as a background task in the container,
# using a sidecar, or via a script configured as credential_process in your AWS config file
```
See also the [credential_process](https://aws.amazon.com/blogs/security/access-aws-using-a-google-cloud-platform-native-workload-identity/#define_IAM_role) example for how to set up a script in your **~/.aws/config** for renewing tokens.


## Multiple GKE Clusters using Google Cloud Identity Platform (GCIP) as OIDC Broker

TODO: Add multi-cluster example using https://docs.cloud.google.com/identity-platform/docs/web/oidc as a single OIDC Issuer that acts as an IdP Broker across the cluster token issuers

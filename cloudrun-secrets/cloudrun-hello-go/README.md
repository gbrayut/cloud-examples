# Cloud Run terraform example

Note: this assumes the project in your [app.tf](./app.tf) file already exists and is already linked to a billing account and that the account used to run terraform has [Cloud Run permissions](https://cloud.google.com/run/docs/reference/iam/roles#additional-configuration).

## Overview

Based on [guillaumeblaquiere/cloudrun-hello-go](https://github.com/guillaumeblaquiere/cloudrun-hello-go) this shows how to print out the Environment Variables and mounted Volumes for accessing secrets, as well as basic API access.

> Mount each secret as a volume, which makes the secret available to the container as files. Reading a volume always fetches the secret value from Secret Manager, so it can be used with the latest version. This method also works well with secret rotation.
>
> Pass a secret using environment variables. Environment variables are resolved at instance startup time, so if you use this method, Google recommends that you pin the secret to a particular version rather than using latest.
For more information, refer to the Secret Manager best practices document.

The third way of accessing secrets is directly using [Cloud APIs](https://cloud.google.com/secret-manager/docs/reference/libraries). This approach can be a bit more work but give full contron and is slightly more secure since it [prevents](https://cloud.google.com/secret-manager/docs/best-practices#coding_practices) some attack vectors, but for the vast majority of case any of the above methods should be fine.

```bash
cd cloudrun-secrets/cloudrun-hello-go

# Test locally
go run .
curl localhost:8080

# Deploy to cloudrun (Make sure to also update image/entrypoints in app.tf)
gcloud run deploy my-service --source ../cloudrun-hello-go --region us-central1

# If you just want to build a one-off image in Artifact Registry, you can use:
DEVSHELL_PROJECT_ID=gregbray-12345 # Usually set automatically in Cloud Shell
gcloud services enable --project=$DEVSHELL_PROJECT_ID cloudbuild.googleapis.com run.googleapis.com artifactregistry.googleapis.com iamcredentials.googleapis.com

gcloud builds submit --pack image=us-central1-docker.pkg.dev/$DEVSHELL_PROJECT_ID/cloud-run-source-deploy/cloudrun-hello-go:latest ../cloudrun-hello-go
echo image = "us-central1-docker.pkg.dev/$DEVSHELL_PROJECT_ID/cloud-run-source-deploy/cloudrun-hello-go"


# Results accessing this cloudrun-hello-go site (Raw plain-text output instead of HTML)
This created the revision my-service-00010-leg of the Cloud Run service my-service in the GCP project gregbray-12345

Environment:
CNB_GROUP_ID=1000
CNB_STACK_ID=google
HOME=/home/cnb
PWD=/workspace
DEBIAN_FRONTEND=noninteractive
PORT=8080
CNB_USER_ID=1000
K_CONFIGURATION=my-service
K_REVISION=my-service-00010-leg
K_SERVICE=my-service
SECRET_ENV_VAR_FAKE=secret-data
PATH=/layers/google.go.build/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

Secrets:
not-a-real-secret=secret-data
```

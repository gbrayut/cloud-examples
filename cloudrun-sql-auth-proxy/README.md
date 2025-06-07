# Cloud Run SQL Auth Proxy Example

Google Cloud Run can use the [Cloud SQL Language Connector](https://cloud.google.com/sql/docs/mysql/language-connectors) libraries to add encryption and IAM based authorization when connecting to a Cloud SQL Instance. Alternatively, the [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/mysql/sql-proxy) can be used as either a fully managed [Cloud Run Integration](https://cloud.google.com/sql/docs/mysql/connect-run) or as a sidecar if you need custom configuration.

## Cloud SQL Integration for Cloud Run

As of May 2025 the Cloud Run built-in Cloud SQL integration uses the instance's public IP (if available) or uses the Private IP via Serverless VPC Connector or Direct VPC access if the SQL instance does not have a public IP. If you add a public IP to the SQL instance in the future, then Cloud Run will implicitly start using the Public IP.

When you configure the integration using `--add-cloudsql-instances=...` or the Cloud SQL connections section of a Cloud Run revision, it simply adds the `run.googleapis.com/cloudsql-instances: PROJECT-ID:REGION:INSTANCE-NAME` annotation to your service. You will not see the cloud-sql-proxy container or service and will not be able to change any configuration settings. For instance, [auto-iam-authn](https://cloud.google.com/sql/docs/postgres/iam-authentication#auto-iam-auth) is not currently supported when using the managed Cloud Run integraion and instead requires using the sidecar version.

The following example is based on [GoogleCloudPlatform/python-docs-samples](https://github.com/GoogleCloudPlatform/python-docs-samples/blob/main/cloud-sql/mysql/sqlalchemy/README.md#deploy-to-cloud-run) and shows how to configure a Python service with SQLAlchemy to securely connect to Mysql using the built-in Cloud SQL integration.

```bash
PROJECT_ID=gregbray-run
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# https://cloud.google.com/sql/docs/mysql/create-instance
# https://cloud.google.com/sdk/gcloud/reference/sql/instances/create
gcloud sql instances create test-instance --project=$PROJECT_ID \
    --region=us-central1 \
    --tier=db-g1-small \
    --database-version=MYSQL_8_0 \
    --edition=ENTERPRISE
CLOUDSQL_NAME="$PROJECT_ID:us-central1:test-instance"

# Create named superuser https://cloud.google.com/sdk/gcloud/reference/sql/users/create
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
gcloud sql users create test-user --instance="test-instance" --project=$PROJECT_ID \
    --password="$PASSWORD" --type="BUILT_IN" --host='%'

gcloud sql databases create test-db --instance="test-instance" --project=$PROJECT_ID

# Clone and Deploy Cloud Run service
git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
cd python-docs-samples/cloud-sql/mysql/sqlalchemy/

# Configure Google Service Accounts and Deploy from source permissions
# https://cloud.google.com/run/docs/deploying-source-code
gcloud iam service-accounts create cloud-sql-demo --project=$PROJECT_ID \
    --description="Custom service account for Cloud Run demo"
# Grant service account access to cloud sql instance (for mapping name to full connection string)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:cloud-sql-demo@$PROJECT_ID.iam.gserviceaccount.com" \
  --role=roles/cloudsql.client

# Optional custom build account (instead of default PROJECT_NUMBER-compute@developer.gserviceaccount.com)
gcloud iam service-accounts create my-build-account --project=$PROJECT_ID \
    --description="Custom build account for Cloud Run demo"
gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:my-build-account@$PROJECT_ID.iam.gserviceaccount.com" \
      --role="roles/run.builder"

# Cloud Run with SQL Connector https://cloud.google.com/sql/docs/mysql/connect-run
# add-cloudsql-instances just adds run.googleapis.com/cloudsql-instances annotation
# https://cloud.google.com/sdk/gcloud/reference/run/deploy
gcloud run deploy cloud-sql-demo --region us-central1 --project=$PROJECT_ID \
    --source . --allow-unauthenticated \
    --add-cloudsql-instances="$CLOUDSQL_NAME" \
    --service-account="cloud-sql-demo@$PROJECT_ID.iam.gserviceaccount.com" \
    --build-service-account="projects/$PROJECT_ID/serviceAccounts/my-build-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --set-env-vars INSTANCE_UNIX_SOCKET=/cloudsql/$CLOUDSQL_NAME \
    --set-env-vars DB_USER='test-user',DB_PASS=$PASSWORD,DB_NAME='test-db'



# Or use Cloud Run direct IAP Integration (in beta preview) for web user authentication
# https://cloud.google.com/iap/docs/enabling-cloud-run#gcloud
gcloud beta services identity create --service=iap.googleapis.com --project=$PROJECT_ID
# beta options https://cloud.google.com/sdk/gcloud/reference/beta/run/deploy
gcloud beta run deploy cloud-sql-demo --region us-central1 --project=$PROJECT_ID \
    --source . --iap --no-allow-unauthenticated \
    --add-cloudsql-instances="$CLOUDSQL_NAME" \
    --service-account="cloud-sql-demo@$PROJECT_ID.iam.gserviceaccount.com" \
    --build-service-account="projects/$PROJECT_ID/serviceAccounts/my-build-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --set-env-vars INSTANCE_UNIX_SOCKET=/cloudsql/$CLOUDSQL_NAME \
    --set-env-vars DB_USER='test-user',DB_PASS=$PASSWORD,DB_NAME='test-db'

# Grant end users access to cloud run via IAP (otherwise error: You don't have access)
# https://cloud.google.com/sdk/gcloud/reference/beta/iap/web/add-iam-policy-binding
# See also "edit policy" on security section of Cloud Run Service details
gcloud beta iap web add-iam-policy-binding --region us-central1 --project=$PROJECT_ID \
    --resource-type=cloud-run \
    --service cloud-sql-demo \
    --member="user:my-username@example.com" \
    --role='roles/iap.httpsResourceAccessor'



# Side note: for Cloud SQL Language Connector (in connect_connector.py) this demo 
# would use the following instead of INSTANCE_UNIX_SOCKET
#    --set-env-vars INSTANCE_CONNECTION_NAME=$CLOUDSQL_NAME \
```

## Cloud Run with Direct VPC, Auth Proxy Sidecar, and Cloud SQL via Private IP

Here is a more elaborate example with Cloud Run [private networking](https://cloud.google.com/run/docs/securing/private-networking), specifically [Direct VPC egress](https://cloud.google.com/run/docs/configuring/vpc-direct-vpc) although the [Serverless VPC Connector](https://cloud.google.com/run/docs/configuring/connecting-vpc#connectors) would also work. This also shows how to configure the SQL Auth Proxy as a sidecar, and configure Cloud SQL to only use a private ip.

The following example is based on [GoogleCloudPlatform/python-docs-samples](https://github.com/GoogleCloudPlatform/python-docs-samples/blob/main/cloud-sql/mysql/sqlalchemy/README.md#deploy-to-cloud-run) and shows how to configure a Python service with SQLAlchemy to securely connect to Mysql using the built-in Cloud SQL integration.

```bash
PROJECT_ID=gregbray-run
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Create demo VPC and subnets. See direct vpc docs for details on using existing or shared VPC
# Note: this new subnet does NOT have Cloud NAT and therefore cannot be used to access public ips
# It can however still reach googleapis.com via Private Google Access
gcloud compute networks create demo-vpc --subnet-mode=custom --project $PROJECT_ID
gcloud compute networks subnets create cloud-run-demo-subnet \
    --network "projects/$PROJECT_ID/global/networks/demo-vpc" \
    --region us-central1 --range 10.0.100.0/24 --enable-private-ip-google-access

# Create static addressess range and Service Networking peering
gcloud compute addresses create google-service-networking-subnet \
    --global --purpose=VPC_PEERING --addresses=10.60.0.0 --prefix-length=20  \
    --network="projects/$PROJECT_ID/global/networks/demo-vpc" \
    --description="Private IP range for Google managed services"
gcloud services vpc-peerings connect --project $PROJECT_ID \
    --service=servicenetworking.googleapis.com \
    --ranges=google-service-networking-subnet \
    --network=demo-vpc

# Create a Cloud SQL instance using Private Service Acccess https://cloud.google.com/sql/docs/mysql/connect-instance-private-ip
# https://cloud.google.com/sdk/gcloud/reference/sql/instances/create
gcloud sql instances create psa-instance --project=$PROJECT_ID --region=us-central1 \
    --tier=db-g1-small --database-version=MYSQL_8_0 --edition=ENTERPRISE \
    --no-assign-ip --connector-enforcement="REQUIRED" \
    --network="demo-vpc"






PSASQL_NAME="$PROJECT_ID:us-central1:psa-instance"

# Create named superuser https://cloud.google.com/sdk/gcloud/reference/sql/users/create
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
gcloud sql users create test-user --instance="psa-instance" --project=$PROJECT_ID \
    --password="$PASSWORD" --type="BUILT_IN" --host='%'
gcloud sql databases create test-db --instance="psa-instance" --project=$PROJECT_ID

gcloud beta run deploy cloud-sql-vpc-demo --region us-central1 --project=$PROJECT_ID \
    --source . --iap --no-allow-unauthenticated --vpc-egress="all-traffic" \
    --network="demo-vpc" --subnet="projects/${PROJECT_ID}/regions/us-central1/subnetworks/cloud-run-demo-subnet" \
    --add-cloudsql-instances="$PSASQL_NAME" \
    --service-account="cloud-sql-demo@$PROJECT_ID.iam.gserviceaccount.com" \
    --build-service-account="projects/$PROJECT_ID/serviceAccounts/my-build-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --set-env-vars INSTANCE_UNIX_SOCKET=/cloudsql/$PSASQL_NAME \
    --set-env-vars DB_USER='test-user',DB_PASS=$PASSWORD,DB_NAME='test-db'

# This time use Conditional IAM to grant IAP access to all cloud-sql-vpc-demo deployments in any region
# https://cloud.google.com/iap/docs/managing-access#resources_and_permissions
# See also https://cloud.google.com/iam/docs/conditions-resource-attributes#resource-name
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --role=roles/iap.httpsResourceAccessor \
  --member="user:my-username@example.com" \
  --condition-from-file=<(cat <<- END
---
title: allow_iap_vpcdemo_cloud_run_allregions
description: Conditional allow based on resource names
expression: |-
  resource.name.startsWith('projects/57191817468/iap_web/cloud_run-') &&
  request.host.startsWith('cloud-sql-vpc-demo')
END
)

```

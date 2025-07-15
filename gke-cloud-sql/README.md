# Cloud SQL Demo on GKE

From https://github.com/GoogleCloudPlatform/python-docs-samples/tree/main/cloud-sql/mysql/sqlalchemy

Similar to https://github.com/gbrayut/cloud-examples/tree/main/cloudrun-sql-auth-proxy

TODO: Clean these notes up

```
PROJECT_ID=gregbray-vpc
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud sql instances create test-instance --project=$PROJECT_ID \
    --region=us-central1 \
    --tier=db-g1-small \
    --database-version=MYSQL_8_0 \
    --edition=ENTERPRISE
CLOUDSQL_NAME="$PROJECT_ID:us-central1:test-instance"

#TODO: Switch above to PSA (current) or PSC

PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
gcloud sql users create test-user --instance="test-instance" --project=$PROJECT_ID \
    --password="$PASSWORD" --type="BUILT_IN" --host='%'

gcloud sql databases create test-db --instance="test-instance" --project=$PROJECT_ID

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$PROJECT_ID.svc.id.goog[cloud-sql-demo/default]" \
  --role=roles/cloudsql.client --condition None

kubectl create ns cloud-sql-demo
kubectl create secret generic db-password -n cloud-sql-demo --from-literal=password=${PASSWORD}
```

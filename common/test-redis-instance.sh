# Valkey with PSC, IAM, and TLS https://docs.cloud.google.com/sdk/gcloud/reference/memorystore/instances/create
gcloud network-connectivity service-connection-policies create psc-valkey \
    --network=gke-vpc --project=gregbray-vpc --region=us-central1 \
    --service-class=gcp-memorystore \
    --subnets=gke-iowa-subnet \
    --description="allow valkey pscAutoConnection endpoints"
gcloud memorystore instances create test \
--location=us-central1 \
--endpoints='[{"connections": [{"pscAutoConnection": {"network": "projects/503076227230/global/networks/gke-vpc", "projectId": "gregbray-vpc"}}]}]' \
--replica-count=1 \
--node-type=standard-small \
--engine-version=VALKEY_8_0 \
--shard-count=1 \
--zone-distribution-config-mode=single-zone \
--zone-distribution-config=us-central1-a \
--mode=cluster-disabled --authorization-mode=iam-auth --transit-encryption-mode=server-authentication

# Create a Test VM with default service account and full GCP scopes
gcloud compute instances create test-vm --project=gregbray-vpc \
  --zone=us-central1-c --machine-type=e2-custom-2-6400 \
  --network-interface "nic-type=GVNIC,network=gke-vpc,subnet=gke-iowa-subnet,no-address" \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --shielded-vtpm --shielded-integrity-monitoring \
  --scopes=cloud-platform

# Without --scopes=cloud-platform the GCE access token will be denied when trying to access memorystore
# best practice recommends overriding the defaults to use the single cloud-platform scope and then
# instead managing access with IAM roles and permissions

# Grant the GCE service account permission to connect to valkey/redis/memcached instances in the project
gcloud projects add-iam-policy-binding gregbray-vpc \
--member="serviceAccount:503076227230-compute@developer.gserviceaccount.com" \
--role="roles/memorystore.dbConnectionUser" --condition=None


#
# The rest of these commands should run inside the new VM after connecting via ssh
#
gcloud compute ssh test-vm --location us-central1-c

# Install client tools (or use https://valkey.io/topics/installation/)
sudo apt update; sudo apt install redis-tools

# Download the server-ca.pem from console and copy to VM https://console.cloud.google.com/memorystore/valkey
# TODO generate pem file from: gcloud memorystore instances get-certificate-authority test --location us-central1

# Test connection inside vm
TOKEN=$(gcloud auth print-access-token)
redis-cli -h 10.31.232.35 -c --tls  --cacert server-ca.pem --user default --pass $TOKEN
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
10.31.232.35:6379> PING
PONG
10.31.232.35:6379> 

# If you see this error it likely means your user account does not have permissions 
# or the GCE VM has cloud-platform scope disabled for the service account (see VM instance in console)
AUTH failed: WRONGPASS invalid username-password pair or user is disabled.

# You can check the active credentials using:
gcloud auth list
ACTIVE  ACCOUNT
*       503076227230-compute@developer.gserviceaccount.com

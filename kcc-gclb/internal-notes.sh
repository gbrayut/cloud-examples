# Test VMs
gcloud compute instances create test-iowa --project=gregbray-vpc \
  --zone=us-central1-c --machine-type=e2-custom-2-6400 \
  --network-interface "nic-type=GVNIC,network=gke-vpc,subnet=gke-iowa-subnet,no-address" \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --shielded-vtpm --shielded-integrity-monitoring

gcloud compute instances create test-oregon --project=gregbray-vpc \
  --zone=us-west1-c --machine-type=e2-custom-2-6400 \
  --network-interface "nic-type=GVNIC,network=gke-vpc,subnet=gke-oregon-subnet,no-address" \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --shielded-vtpm --shielded-integrity-monitoring



gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag --allow tcp:80


gcloud compute addresses create network-lb-ip-1 \
    --region us-central1


gcloud dns --project=vpc-project record-sets create \
  vm.example.com. --zone="example" --type="A" \
  --ttl="10" --routing-policy-type="FAILOVER" --enable-health-checking \
  --routing-policy-primary-data="projects/gke-project/regions/us-west1/forwardingRules/a321f0be283a140b596e0ec52008fae1" \
  --backup-data-trickle-ratio="0.0" --routing-policy-backup-data-type="GEO" \
  --routing-policy-backup-data="us-west1=projects/gke-project/regions/us-west3/forwardingRules/ac32a3df087494e7ca0f61c6685050ea"

gcloud dns record-sets create geo.example.com \
--ttl=5 --type=A --zone=example \
--routing-policy-type=GEO \
--routing-policy-data=""filled at lab start"=$US_WEB_IP;placeholder=$EUROPE_WEB_IP"
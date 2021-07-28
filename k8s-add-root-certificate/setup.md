# Overview

This outlines how to setup a private docker registry using self signed TLS certificate and a Kubernetes cluster for testing image pulls

#
## Setup private registry with self signed TLS

Create a new VM for deploying the [Docker Registry](https://docs.docker.com/registry/deploying/) using [self signed TLS](https://docs.docker.com/registry/insecure/#use-self-signed-certificates).


```bash
export CLOUDSDK_CORE_PROJECT=demo2021-310119
export CLOUDSDK_COMPUTE_REGION=us-central1
export CLOUDSDK_COMPUTE_ZONE=us-central1-a

# Create VM for running docker registry
gcloud compute instances create test-registry --machine-type=e2-medium --subnet=default --no-address --tags=https-server --boot-disk-size=20GB --shielded-secure-boot --shielded-vtpm

# Create firewall rule to allow https traffic to tagged VMs
gcloud compute --project=demo2021-310119 firewall-rules create default-allow-https --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 --target-tags=https-server

# SSH to new VM and setup port forwarding (local 8443 -> VM 443)
gcloud compute ssh test-registry --tunnel-through-iap -- -L 8443:localhost:443

# In the VM: Create new self-signed certs for test-registry
# https://docs.docker.com/registry/insecure/#use-self-signed-certificates
mkdir -p certs
openssl req -newkey rsa:4096 -nodes -sha256 -keyout certs/domain.key \
  -subj "/CN=test-registry/ST=state/L=city/O=testing/OU=company" \
  -addext "subjectAltName = DNS:test-registry,DNS:`hostname -f`" \
  -x509 -days 365 -out certs/domain.crt

# In the VM, start a docker registry container listening via TLS on VM port 443
docker run -d --restart=always --name registry \
  -v "$(pwd)"/certs:/certs   -e REGISTRY_HTTP_ADDR=0.0.0.0:8443 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -p 443:8443 registry:2

# Configure VM to trust the new cert
sudo cp certs/domain.crt /usr/local/share/ca-certificates/
sudo update-ca-certificate
sudo systemctl restart docker

# copy an image to the registry 
# https://docs.docker.com/registry/deploying/#copy-an-image-from-docker-hub-to-your-registry
docker pull marketplace.gcr.io/google/debian10
docker tag marketplace.gcr.io/google/debian10 test-registry:443/test-debian
docker push test-registry:443/test-debian

# Test connectivity locally (or via ssh forwarding on 8443) using curl
curl -kv --resolve test-registry:443:127.0.0.1 https://test-registry:443

# Test docker pull on VM
docker image rm test-registry:443/test-debian 
docker images
docker image pull test-registry:443/test-debian 
docker images

# Should now be ready to setup and test Kubernetes Cluster (see below)

# When finished or if you want to start fresh, force remove the container and certs
docker rm -f registry
rm -rf certs/*
```

#
## Setup cluster and deployment for testing

Setup a test cluster in the same subnet using cos_containerd nodes.

```bash
gcloud beta container --project "demo2021-310119" clusters create "test-cluster" \
  --cluster-version "1.20.8-gke.900" --enable-private-nodes --image-type "COS_CONTAINERD" \
  --master-ipv4-cidr "172.16.0.0/28" --machine-type "e2-standard-2" --disk-type "pd-standard" --disk-size "100" \
  --metadata disable-legacy-endpoints=true --num-nodes "2" --enable-stackdriver-kubernetes \
  --enable-ip-alias --network "projects/demo2021-310119/global/networks/default" --subnetwork "projects/demo2021-310119/regions/us-central1/subnetworks/default" \
  --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "0" --max-nodes "3" \
  --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 \
  --enable-shielded-nodes --shielded-secure-boot --shielded-integrity-monitoring \
  --no-enable-master-authorized-networks
```

Once the cluster is available, you are ready to start testing

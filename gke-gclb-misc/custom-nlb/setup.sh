# Custom NLB reusing GKE NEG. Modified from https://cloud.google.com/load-balancing/docs/internal/setting-up-internal-zonal-neg#configure_the_load_balancer
# See also https://github.com/gbrayut/cloud-examples/tree/main/gke-gclb-misc/custom-nlb/ds-whereami.yaml
PROJECT_ID=gregbray-gke-v1
gcloud config set core/project $PROJECT_ID

# This doesn't work unless the port and server are available via node ip (hostNetwork: true)
gcloud compute health-checks create \
    http hc-http-80 --region=us-central1 --port=80

# Can instead reuse the kubelet port 10256 /healthz "...-l4-shared-hc" check created by GKE subsetting NLB
gcloud compute health-checks list
gcloud compute backend-services create be-ilb \
    --load-balancing-scheme=internal \
    --protocol=tcp \
    --region=us-central1 \
    --health-checks=k8s2-j71w3amp-l4-shared-hc

# for hc-http-80 or other regional check add
    --health-checks-region=us-central1

# Cannot use standalone neg (GCE_VM_IP_PORT) for passthru NLB (requires GCE_VM_IP)
gcloud compute backend-services add-backend be-ilb \
   --network-endpoint-group test-standalone \
   --network-endpoint-group-zone=us-central1-a \
   --region=us-central1
ERROR: (gcloud.compute.backend-services.add-backend) Could not fetch resource:
 - Invalid value for field 'resource.backends[0].group': 'https://compute.googleapis.com/compute/v1/projects/gregbray-gke-v1/zones/us-central1-a/networkEndpointGroups/test-standalone'.
   Only GCE_VM_IP or port mapping network endpoint groups can be used by an INTERNAL L4 backend service.

# Using the NEGs for each zone from subsetting NLB should work
gcloud compute backend-services add-backend be-ilb \
   --network-endpoint-group k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9 \
   --network-endpoint-group-zone=us-central1-a \
   --region=us-central1
gcloud compute backend-services add-backend be-ilb \
   --network-endpoint-group k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9 \
   --network-endpoint-group-zone=us-central1-c \
   --region=us-central1
gcloud compute backend-services add-backend be-ilb \
   --network-endpoint-group k8s2-j71w3amp-test-gclb-whereami-spread-new-jaxls3y9 \
   --network-endpoint-group-zone=us-central1-f \
   --region=us-central1

# Then create the Forwarding Rule with multple ports for testing different routing options
gcloud compute forwarding-rules create fr-ilb \
    --region=us-central1 \
    --load-balancing-scheme=internal \
    --network=gke-vpc \
    --subnet=gke-iowa-subnet \
    --address=10.31.232.13 \
    --ip-protocol=TCP \
    --ports=80,18080,30080,32106 \
    --backend-service=be-ilb \
    --backend-service-region=us-central1 \
    --allow-global-access
# 32106 is from an auto generated NodePort on existing NLB (kubectl describe -n test-gclb svc/whereami-spread)
# Note: may also need to configure firewall rules for 0.0.0.0->gke node IP:port

# Can then test using options like

curl -vs http://10.31.232.10  # whereami-spread original NLB (no-subsetting)
curl -vs http://10.31.232.11  # whereami-spread-new subsetting NLB (after editing name and re-applying ds-whereami.yaml)

curl -vs http://10.31.232.13:80     # This would only work using Option 1 (pod with hostNetwork: true, PORT 80) or Option 3 (externalIP on Service resource)
curl -vs http://10.31.232.13:18080  # This would only work using Option 1 (pod with hostNetwork: true, PORT 18080)
curl -vs http://10.31.232.13:30080  # This would only work using Option 2 (explicit nodePort)
curl -vs http://10.31.232.13:32106  # This uses whatever nodeport was assigned to the existing NLB

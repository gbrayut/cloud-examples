# First verify standalone negs from 01-caddy-backend.yaml were created (one per zone where pods are active)
gcloud compute network-endpoint-groups describe caddy-tls --zone us-central1-f

creationTimestamp: '2026-06-23T13:40:12.650-07:00'
description: '{"cluster-uid":"4b3baf9a-268d-4085-b6fc-048a1937ce2e","namespace":"caddy","service-name":"caddy-sa-neg","port":"443"}'
id: '6538576421103030723'
kind: compute#networkEndpointGroup
name: caddy-tls
network: https://www.googleapis.com/compute/v1/projects/gregbray-vpc/global/networks/gke-vpc
networkEndpointType: GCE_VM_IP_PORT
selfLink: https://www.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-f/networkEndpointGroups/caddy-tls
size: 1
subnetwork: https://www.googleapis.com/compute/v1/projects/gregbray-vpc/regions/us-central1/subnetworks/gke-gke-iowa-subnet-12f7b9e4
zone: https://www.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-f


# Configure globally managed proxy subnets for each region
# Similar to https://docs.cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-cross-reg-internal#gcloud_1
gcloud compute networks subnets create proxy-iowa-global \
  --purpose=GLOBAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=us-central1 \
  --network "projects/gregbray-vpc/global/networks/gke-vpc" \
  --range=10.210.0.0/23
gcloud compute networks subnets create proxy-oregon-global \
  --purpose=GLOBAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=us-west1 \
  --network "projects/gregbray-vpc/global/networks/gke-vpc" \
  --range=10.210.2.0/23

# create firewall rules https://docs.cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#configure_firewall_rules
NODENETWORKTAG="gke-gke-iowa-12f7b9e4-node,gke-gke-oregon-65a2c6d2-node"
gcloud compute firewall-rules create fw-allow-health-checks \
  --network=gke-vpc --action=allow --direction=ingress \
  --description="Allow managed health check IP ranges to access any target port on nodes/pods" \
  --source-ranges="35.191.0.0/16,130.211.0.0/22,209.85.152.0/22,209.85.204.0/22" \
  --target-tags=$NODENETWORKTAG \
  --rules=tcp
gcloud compute firewall-rules create fw-allow-crilb-proxies \
  --network=gke-vpc --action=allow --direction=ingress \
  --description="Allow Global Managed Proxy subnet ranges to access target ports on pods" \
  --source-ranges=10.210.0.0/22 --target-tags=$NODENETWORKTAG \
  --rules=tcp:8443

# Create a generic http health check. https://docs.cloud.google.com/sdk/gcloud/reference/compute/health-checks/create/http
#gcloud compute health-checks create http global-http-health-check \
#  --global --port 8080

# For caddy we'll use a specific https check instead https://docs.cloud.google.com/sdk/gcloud/reference/compute/health-checks/create/https
gcloud compute health-checks create https global-caddy-health-check \
   --global --check-interval="10s" --host "example.com" --use-serving-port

# Configure Backend Service and add standalone negs
gcloud compute backend-services create example-tls-bes \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=TCP --health-checks=global-caddy-health-check \
  --global-health-checks --global

# https://docs.cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#add_backends
gcloud compute backend-services add-backend example-tls-bes \
  --global --network-endpoint-group="caddy-tls" \
  --network-endpoint-group-zone="us-central1-f" \
  --balancing-mode CONNECTION --max-connections-per-endpoint=100
# Repeat for all regions/zones where the service is active

# Create Cross Region Proxy LB but exclude reference to backends
gcloud beta compute target-tcp-proxies create crilb-example-tls \
  --load-balancing-scheme=INTERNAL_MANAGED --proxy-header NONE --global

# Create tlsroute for SNI based domain routing
PROJECT_ID=gregbray-vpc
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
BACKEND_SERVICE=example-tls-bes     # Shared backend in this case but usually there is one bes per target service
cat <<EOF | tee /tmp/tls_route.yaml
name: tls-route
targetProxies:
- projects/$PROJECT_NUMBER/locations/global/targetTcpProxies/crilb-example-tls
rules:
- matches:
  - sniHost:
    - example.com
    - caddy.example.com
  action:
   destinations:
   - serviceName: projects/$PROJECT_NUMBER/locations/global/backendServices/$BACKEND_SERVICE
- matches:
  - sniHost:
    - example.net
  action:
   destinations:
   - serviceName: projects/$PROJECT_NUMBER/locations/global/backendServices/$BACKEND_SERVICE
EOF

# https://docs.cloud.google.com/sdk/gcloud/reference/network-services/tls-routes/import
gcloud network-services tls-routes import example-tlsroute \
  --source /tmp/tls_route.yaml --location global

# Create listeners in multiple regions
gcloud compute forwarding-rules create example-tls-west-fr \
  --load-balancing-scheme INTERNAL_MANAGED \
  --network gke-vpc --subnet gke-oregon-subnet --subnet-region us-west1 \
  --ports 443 --target-tcp-proxy crilb-example-tls --global
gcloud compute forwarding-rules create example-tls-central-fr \
  --load-balancing-scheme INTERNAL_MANAGED \
  --network gke-vpc --subnet gke-iowa-subnet --subnet-region us-central1 \
  --ports 443 --target-tcp-proxy crilb-example-tls --global

# Get IP Address assignments
gcloud compute forwarding-rules list --filter "target:crilb-example-tls"
NAME                    REGION  IP_ADDRESS    IP_PROTOCOL  TARGET
example-tls-central-fr          10.31.232.61  TCP          crilb-example-tls
example-tls-west-fr             10.28.236.60  TCP          crilb-example-tls

# Test SNI routing using curl and forced dns resolution
curl -vsk --resolve example.com:443:10.31.232.61 https://example.com
curl -vsk --resolve example.net:443:10.28.236.60 https://example.net
curl -vsk --resolve caddy.example.com:443:10.28.236.60 https://caddy.example.com

# If not working see health check status at https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers
# Can also use connectivity test to make sure health check -> pods and proxy -> pods traffic is allowed on target container ports
# https://console.cloud.google.com/net-intelligence/connectivity/tests/list

# Configure GEO DNS Routing for each domain (or use prod-crilb.example.com and configure other domains as cname)
# https://docs.cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-cross-reg-internal#dns-policy-manager
gcloud dns record-sets create caddy.example.com --ttl="30" \
  --type="A" --zone="example" \
  --routing-policy-type="GEO" \
  --routing-policy-data="us-central1=example-tls-central-fr@global;us-west1=example-tls-west-fr@global" \
  --enable-health-checking

# Verify DNS lookup and GEO routing works
gregbray@test-vm:~$ curl -vsk https://caddy.example.com
* Host caddy.example.com:443 was resolved.
* IPv6: (none)
* IPv4: 10.31.232.61
*   Trying 10.31.232.61:443...
* Connected to caddy.example.com (10.31.232.61) port 443
...
< HTTP/2 200
< alt-svc: h3=":8443"; ma=2592000
< content-type: text/plain; charset=utf-8
< server: Caddy
< x-testing: this is a test 123
< content-length: 61
< date: Tue, 23 Jun 2026 22:48:34 GMT
<
success on https
      host: caddy.example.com
      path: /
* Closing connection
* TLSv1.3 (OUT), TLS alert, close notify (256):

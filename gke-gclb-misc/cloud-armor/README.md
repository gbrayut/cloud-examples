# GKE Gateway Example Cloud Armor Policy

```shell
# Manual rule creation via gcloud (for Global use --global) 
# https://cloud.google.com/sdk/gcloud/reference/compute/security-policies/create
gcloud compute security-policies create uc1-security-policy --region us-central1 \
    --description "Test Cloud Armor regional security policy"

# Add security rules https://cloud.google.com/sdk/gcloud/reference/compute/security-policies/rules/create
gcloud compute security-policies rules create 1000 --region us-central1 \
    --security-policy uc1-security-policy \
    --description="allow cidr range" --src-ip-ranges="172.59.0.0/16,1.1.1.1" \
    --action allow

# Change default rule to deny
gcloud compute security-policies rules update 2147483647 --region us-central1 \
    --security-policy uc1-security-policy --action deny-403 \
    --description="default deny all" --src-ip-ranges="*"
    
# Any changes to the rules will take a few minutes to become active


#
# Testing
#

# kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/refs/heads/main/gke-gclb-misc/base-whereami.yaml
# kubectl apply -f https://raw.githubusercontent.com/gbrayut/cloud-examples/refs/heads/main/gke-gclb-misc/cloud-armor/gateway.yaml

# kubectl get pod,svc,gateway -n test-gclb 
# kubectl get events -n test-gclb
# kubectl describe gtw -n test-gclb test-armor


GW_IP=$(kubectl get -n test-gclb gateway/test-armor -o jsonpath='{.status.addresses[0].value}')

# This should generate a 302 redirect to the Gateway API docs as only the Backend Services are blocked
curl -is -H "host: example.com" http://$GW_IP/docs

# This should return the whereami response unless it is blocked by Cloud Armor policy
curl -vs -H "host: example.com" http://$GW_IP/ | jq .
```
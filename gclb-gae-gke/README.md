# Cross Project Google Cloud Load Balancer example

Note: this assumes the project in your [main.tf](./main.tf) file already exists and is already linked to a billing account and that the account used to run terraform has [Cloud Run permissions](https://cloud.google.com/run/docs/reference/iam/roles#additional-configuration).

## Overview

```bash
cd gclb-gae-gke
terraform init
terraform apply
```

https://cloud.google.com/sdk/gcloud/reference/compute/network-endpoint-groups/create#--app-engine-service

https://cloud.google.com/sdk/gcloud/reference/beta/compute/network-endpoint-groups/create#--cloud-function-url-mask

gcloud beta compute network-endpoint-groups create gae-neg \
    --project=demo2021-310119 \
    --region=us-central1 \
    --network-endpoint-type=serverless  \
    --serverless-deployment-platform=appengine.googleapis.com \
    --serverless-deployment-resource=default \
    --serverless-deployment-version=v1

serverless-deployment-platform=appengine.googleapis.com \
serverless-deployment-resource=default \
serverless-deployment-version=v1 \
serverless-deployment-url-mask

# This one worked
gcloud beta compute network-endpoint-groups create gae-neg \
    --project=gregbray-gke \
    --region=us-central1 --network-endpoint-type=serverless \
    --app-engine-app --app-engine-service=default --app-engine-version=v1


gcloud container clusters get-credentials --region us-central1 gke
then create a standalone neg https://cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg
adding annotation to clusterip service
    cloud.google.com/neg: '{"exposed_ports": {"80":{"name": "gke-frontend-neg"}}}'


https://cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#attaching-ext-https-lb

gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
   --network=gke-vpc \
   --action=allow \
   --direction=ingress \
   --target-tags=gke-gke-bb8dbfb1-node \
   --source-ranges=130.211.0.0/22,35.191.0.0/16 \
   --rules=tcp:8080

gcloud compute addresses create hostname-server-vip \
    --ip-version=IPV4 --global --project=gregbray-gke

hostname-server-vip  35.241.28.170

gcloud compute health-checks create http http-basic-check \
    --use-serving-port

gcloud compute backend-services create my-bes \
    --protocol HTTP \
    --health-checks http-basic-check \
    --global

gcloud compute url-maps create web-map \
    --default-service my-bes

gcloud compute target-http-proxies create http-lb-proxy \
    --url-map web-map

gcloud compute forwarding-rules create http-forwarding-rule \
    --address=35.241.28.170 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80

gcloud compute backend-services add-backend my-bes --global \
    --network-endpoint-group=gke-frontend-neg \
    --network-endpoint-group-zone=us-central1-f \
    --balancing-mode RATE --max-rate-per-endpoint


todo: replace hello world with git@github.com:stefanprodan/podinfo.git so it doesn't 404

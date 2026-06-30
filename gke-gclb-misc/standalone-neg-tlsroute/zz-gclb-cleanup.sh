gcloud network-services tls-routes delete example-tlsroute --location global --quiet
# question: does above fix th "failed to fetch" error at https://console.cloud.google.com/kubernetes/gateways

gcloud compute forwarding-rules delete example-tls-central-fr --global --quiet
gcloud compute forwarding-rules delete example-tls-west-fr --global --quiet

gcloud beta compute target-tcp-proxies delete crilb-example-tls --global --quiet

#gcloud network-services tls-routes delete example-tlsroute --location global

gcloud compute backend-services delete example-tls-bes --global --quiet

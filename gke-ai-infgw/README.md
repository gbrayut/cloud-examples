# GKE Inference Gateway

[Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) is an official Kubernetes project in alpha 0.4 status (as of June 2025) that optimizes serving Generative Models on Kubernetes. It allows you to create a unified [inferencing endpoint](https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/main/docs/proposals/003-model-server-protocol/README.md) (based on OpenAI's Completions and Chat APIs) that can [serve multiple models](https://gateway-api-inference-extension.sigs.k8s.io/guides/serve-multiple-genai-models/) or use a single deployment with [LoRA adapters](https://gateway-api-inference-extension.sigs.k8s.io/guides/serve-multiple-lora-adapters/) for different inference use cases. The [Implementer's Guide](https://gateway-api-inference-extension.sigs.k8s.io/guides/implementers/) provides a good overview of how things work (project is gaining traction across [multiple Gateway providers](https://gateway-api-inference-extension.sigs.k8s.io/implementations/gateways/)), and they are creating [new releases](https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases) on a quick cadence with an aggressive [roadmap](https://kubernetes.io/blog/2025/06/05/introducing-gateway-api-inference-extension/#roadmap) (similar to the early days of Gateway API).

[GKE Inference Gateway](https://cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway) is a preview enhancement of the existing regional external (gke-l7-regional-external-managed) or internal ALB (gke-l7-rilb) GatewayClass resources. This example will focus on Gemma 3 models using the vLLM inference server but [Triton](https://gateway-api-inference-extension.sigs.k8s.io/implementations/model-servers/) is also supported.

![infgw body based routing](https://gateway-api-inference-extension.sigs.k8s.io/images/serve-mul-gen-AI-models.png)

# Example Cluster Setup

This setup follows the [Gemma on GKE with vLLM](https://cloud.google.com/kubernetes-engine/docs/tutorials/serve-gemma-gpu-vllm) guide, requires a [Hugging Face token](https://huggingface.co/docs/hub/security-tokens), and your HF user account **must accept** the [Gemma license](https://huggingface.co/google/gemma-3-4b-it). The cluster must also have [Managed Service for Prometheus](https://cloud.google.com/stackdriver/docs/managed-prometheus), which is now enabled by default in GKE, along with the Custom Metrics Stackdriver Adapter (instructions below). The [vllm-gemma3-1b.yaml](./vllm-gemma3-1b.yaml) and [vllm-gemma3-4b.yaml](./vllm-gemma3-4b.yaml) deployments will run on Nvidia G2 VMs which are low cost and readily available. The [gradio.yaml](./gradio.yaml) manifest creates a basic chat web UI that uses the Gemma 1B vllm deployment via the Kubernetes service.

This should not be considered a production ready deployment as you likely will want to use fully baked container images (vs downloading from HF) and tune the values for HPA/HealthChecks/Timeouts/Probes/etc.

```shell
# Variables used throughout this example (Update these for your specific environment)
PROJECT_ID=my-project
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLUSTER_NAME=my-gke-cluster
HF_TOKEN=hf_12345REDACTED   # Hugging Face user must accept the Gemma license linked above.
BASE=https://raw.githubusercontent.com/gbrayut/cloud-examples/refs/heads/main/gke-ai-infgw    # Or use local path to cloned repo

# Add gpu node pool. See https://cloud.google.com/kubernetes-engine/docs/tutorials/serve-gemma-gpu-vllm#create-cluster
# each g2-standard-8 has one L4 GPU with 24GB GDDR6, 8 vCPU, 32GB RAM, and costs ~$2 an hour
gcloud container node-pools create gpupool --cluster=my-gke-cluster --project=$PROJECT_ID \
    --machine-type=g2-standard-8 --accelerator type=nvidia-l4,count=1,gpu-driver-version=latest \
    --location=us-central1 --node-locations=us-central1-c \
    --num-nodes=0 --enable-autoscaling --min-nodes=0 --max-nodes=5

# Create namespace and Hugging Face credentials
kubectl create ns gemma
kubectl create secret generic hf-secret -n gemma --from-literal=hf_api_token=${HF_TOKEN}

# Create Gemma deployment and wait for it to be ready (usually ~5-10 minutes)
kubectl apply -n gemma -f $BASE/vllm-gemma3-1b.yaml
kubectl wait -n gemma --for=condition=Available --timeout=1800s deployment/vllm-gemma-3-1b
kubectl logs -n gemma -f -l app=vllm-gemma-3-1b

# Create gradio deployment for testing chat completions (deployment uses vllm-gemma-3-1b dns service)
kubectl apply -n gemma -f $BASE/gradio.yaml
kubectl get svc,pod -n gemma
kubectl port-forward -n gemma service/gradio 8080:8080
# Then connect to chat server using http://localhost:8080 (best to use prompts instructing llm to be brief)

# Testing vllm server directly using curl
kubectl port-forward -n gemma service/vllm-gemma-3-1b 8000:8000
curl -is http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
"model": "google/gemma-3-1b-it",
"prompt": "What are the top 5 most popular programming languages? Please be brief.",
"max_tokens": 200
  }'
curl -s http://localhost:8000/v1/models | jq .  # Shows available models in that vllm deployment

# Now create a second Gemma deployment and wait for it to be ready (usually ~5-10 minutes)
kubectl apply -n gemma -f $BASE/vllm-gemma3-4b.yaml
kubectl wait -n gemma --for=condition=Available --timeout=1800s deployment/vllm-gemma-3-4b
kubectl logs -n gemma -f -l app=vllm-gemma-3-4b
kubectl get --raw /api/v1/namespaces/gemma/services/http:vllm-gemma-3-4b:8000/proxy/v1/models | jq .

# And for testing Llama model use
kubectl apply -n gemma -f $BASE/vllm-llama3-3b.yaml
```

# GKE Native External Gateway with Basic HTTPRoute

We'll start with a **gke-l7-regional-external-managed** Application Load Balancer (ALB) and basic HTTPRoutes and then build more complex examples on that shared GCLB. If you want to use an internal LB you can switch the [infgw-external.yaml](./infgw-external.yaml) gatewayClass to **gke-l7-rilb** for a regional internal ALB. The example uses a *.example.com [self-signed wildcard certificate](https://github.com/gbrayut/cloud-examples/blob/main/common/openssl-certs.sh) for HTTPS, but you can omit that entire section if you want to use only HTTP for testing. There also is an HTTP->HTTPS redirect example commented out in the [infgw-httproute-basic.yaml](./infgw-httproute-basic.yaml) file if desired.

```shell
# Deploy gateway and host header based routing
kubectl apply -n gemma -f $BASE/infgw-external.yaml
kubectl apply -n gemma -f $BASE/infgw-httproute-basic.yaml

# Check for IP and wait for LB to get programmed (Could take up to 10 minutes)
kubectl get gateway -n gemma vllm-xlb
# See also https://console.cloud.google.com/kubernetes/gateways for any programming errors/warnings

GW_IP=$(kubectl get -n gemma gateway/vllm-xlb -o jsonpath='{.status.addresses[0].value}')

# This should generate a 302 redirect from http to https if the section in infgw-httproute-basic.yaml is enabled
curl -is -H "host: 4b.example.com" http://$GW_IP/v1/models

# All 1b/4b.example.com requests should route to 1b/4b model deployments
# remaining *.example.com or non-matching hostnames get a 404 response by default from ALB
curl -vs --resolve 1b.example.com:80:$GW_IP http://1b.example.com/v1/models | jq .
curl -s  --resolve 3b.example.com:80:$GW_IP http://3b.example.com/v1/models | jq .
curl -s  --resolve 4b.example.com:80:$GW_IP http://4b.example.com/v1/models | jq .
# or https
curl -kvs --resolve 1b.example.com:443:$GW_IP https://1b.example.com/v1/models | jq .
curl -ks  --resolve 3b.example.com:443:$GW_IP https://3b.example.com/v1/models | jq .
curl -ks  --resolve 4b.example.com:443:$GW_IP https://4b.example.com/v1/models | jq .
```

# GKE Native External Gateway with Body Based Routing

If the primary goal is to create a unified API endpoint serving multiple models (or inference API alongside other HTTP based services), that can be achieved using only the GKE Gateway and a Route Callout [Service Extension](https://cloud.google.com/service-extensions/docs/lb-extensions-overview), which are both Generally Available for Regional ALB. The GKE Inference Gateway will add additional features like more advanced routing and autoscaling, but is currently in preview. This next example will use a simple [Body Based Routing](https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/pkg/bbr) service as a Route Callout to extract the model name from the JSON body and include it as an **X-Gateway-Model-Name** header that can then be used by your HTTPRoute resource (see [infgw-httproute-bbr.yaml](./infgw-httproute-bbr.yaml)). You can also see a rendered version of the chart resources in [manifests/bbr.yaml](./manifests/bbr.yaml) including **GCPRoutingExtension** for configuring the Route Callout.

```shell
# https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/config/charts/body-based-routing
# Note: replace helm install with helm template if you want to see the rendered manifest first
# or use helm upgrade to deploy a newer version when the chart is updated
helm install bbr --namespace gemma \
  --version v0.4.0 \
  --set provider.name=gke \
  --set inferenceGateway.name=vllm-xlb \
oci://registry.k8s.io/gateway-api-inference-extension/charts/body-based-routing

kubectl get pod -n gemma -l app=body-based-router

# This example still needs both the gateway and health checks from the above example
kubectl apply -n gemma -f $BASE/infgw-external.yaml
kubectl apply -n gemma -f $BASE/infgw-httproute-basic.yaml
# Then create a bbr.example.com unified endpoint to route requests based on the X-Gateway-Model-Name header
# The HTTPRoute will also add a x-infgw-selected response header so you can see which route was used
kubectl apply -n gemma -f $BASE/infgw-httproute-bbr.yaml

# It could take 3-10 minutes for the route to propagate (Check Gateways section of Cloud console)
GW_IP=$(kubectl get -n gemma gateway/vllm-xlb -o jsonpath='{.status.addresses[0].value}')
PROMPT="Why is the sky blue? Please be brief."
curl -is --resolve bbr.example.com:80:$GW_IP http://bbr.example.com/v1/completions \
  -H "Content-Type: application/json" \
  -d "{ \"model\": \"google/gemma-3-1b-it\", \"max_tokens\": 200, \"prompt\":\"$PROMPT\" }"
# can also use model google/gemma-3-1b-it and meta-llama/Llama-3.2-3B-Instruct
# For https use curl -kv --resolve bbr.example.com:443:$GW_IP https://...

# For troubleshooting check deployent logs (or follow with -f) and Gateway resource status:
kubectl logs -n gemma deploy/body-based-router
kubectl logs -n gemma deploy/vllm-gemma-3-1b
kubectl describe gtw -n gemma vllm-xlb
kubectl describe httproute -n gemma bbr-gemma3-1b
```

The response should include an **x-infgw-selected: bbr-gemma3-1b** or **bbr-gemma3-4b** header indicating which HTTPRoute was used. If you get a **"fault filter abort"** error that tipically means the ALB can't find a matching HTTPRoute or those routes have not fully propagated yet. Double check your hostnames, parentRefs, and resource manifests along with the [Gateways](https://console.cloud.google.com/kubernetes/gateways) section of Google Cloud Console for more details.

If you see this error it usually means something is wrong with the HTTPRoute:
> {"object":"error","message":"[{'type': 'missing', 'loc': ('body',), 'msg': 'Field required', 'input': None}]","type":"BadRequestError","param":null,"code":400}

# GKE Inference Gateway with BBR and EPP

To create an even more flexible API endpoint, the GKE Inference Gateway builds on the previous examples by adding a layer of indirection (InferencePool for each vLLM deployment, and mapping one or more InferenceModels to each pool) along with custom metric based horizontal autoscaling.

The [vllm-infgw-metrics.yaml](./vllm-infgw-metrics.yaml) manifest configures managed metric collection, and the helm chart (See [manifests/inferencepool-epp.yaml](./manifests/inferencepool-epp.yaml)) creates the InferencePool, -epp deployment and other resources. Those can then be combined with an InferenceModel and used in a custom HTTPRoute (see [infgw-httproute-infp-infm.yaml](./infgw-httproute-infp-infm.yaml)).

```shell
# Create InferencePool and InferenceModel CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.4.0/manifests.yaml
# Create RBAC to allow Managed Prometheus to scrape EPP metrics endpoint. For Autopilot, change namespace at bottom to gke-gmp-system
# See https://gateway-api-inference-extension.sigs.k8s.io/guides/metrics/#scrape-metrics
kubectl apply -f $BASE/vllm-infgw-metrics.yaml

# Create InferencePool resources https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/config/charts/inferencepool#configuration
# Note: replace helm install with helm template if you want to see the rendered manifest first or use helm upgrade to deploy a newer version
INFERENCE_POOL=vllm-gemma-3-1b
helm install ${INFERENCE_POOL} -n gemma \
  --set inferencePool.modelServers.matchLabels.app=${INFERENCE_POOL} \
  --set provider.name=gke \
  --version v0.4.0 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

# Since the 4b model is a separate deployment, it needs it's own InferencePool as well
INFERENCE_POOL=vllm-gemma-3-4b
helm install ${INFERENCE_POOL} -n gemma \
  --set inferencePool.modelServers.matchLabels.app=${INFERENCE_POOL} \
  --set provider.name=gke \
  --version v0.4.0 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

# Same for llama 3b
INFERENCE_POOL=vllm-llama-3-3b
helm install ${INFERENCE_POOL} -n gemma \
  --set inferencePool.modelServers.matchLabels.app=${INFERENCE_POOL} \
  --set provider.name=gke \
  --version v0.4.0 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

# You should now see one -epp pod for each inference pool (inferenceExtension.replicas value defaults to 1)
kubectl get pod -n gemma

# Now create HTTPRoutes that use InferencePools as the backendRefs
# Since the health check is configured as part of the helm chart, we no longer need infgw-httproute-basic.yaml
# InferenceModel resources are required and included in infgw-httproute-infp-infm.yaml
kubectl apply -n gemma -f $BASE/infgw-external.yaml   # Still the same base gateway as before
kubectl apply -n gemma -f $BASE/infgw-httproute-infp-infm.yaml

# It may take 3-10 minutes for the GCLB to update. Check for errors in the httproute 
# or console https://console.cloud.google.com/kubernetes/gateways
kubectl describe httproute -n gemma infp-gemma3-1b

# Follow endpoint picker logs to see routing details
kubectl logs -n gemma deploy/vllm-gemma-3-1b-epp -f

# Test EPP based routing
GW_IP=$(kubectl get -n gemma gateway/vllm-xlb -o jsonpath='{.status.addresses[0].value}')
PROMPT="Why is the sky blue? Please be brief."
curl -is --resolve api.example.com:80:$GW_IP http://api.example.com/v1/completions \
  -H "Content-Type: application/json" \
  -d "{ \"model\": \"google/gemma-3-1b-it\", \"max_tokens\": 200, \"prompt\":\"$PROMPT\" }"
# For https use curl -kvs --resolve api.example.com:443:$GW_IP https://...

# Same as before, look for x-infgw-selected: infp-gemma3-1b or infp-gemma3-4b response header
# There also is a x-went-into-resp-headers: true debug header currently added by epp https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/release-0.4/pkg/epp/handlers/response.go#L133-L134
```

# GKE Inference Gateway HPA Custom Metrics and Load Testing

The EndPoint Picker (EPP) service exposes a set of [inference metrics](https://gateway-api-inference-extension.sigs.k8s.io/guides/metrics-and-observability/). For GKE, the InferencePool helm chart will include a [ClusterPodMonitoring](https://cloud.google.com/stackdriver/docs/managed-prometheus/setup-managed#gmp-pod-monitoring) resource to scrape these metrics so they can be displayed in Cloud Monitoring and used as part of [Custom Metric Horizontal Pod Autoscaler](https://cloud.google.com/kubernetes-engine/docs/tutorials/autoscaling-metrics#custom-metric). The [vllm-infgw-hpas.yaml](./vllm-infgw-hpas.yaml) example uses **inference_pool_average_kv_cache_utilization** as the custom scaling metric and targets an average pod value of 10m (1%) for [desired replica](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) calculations (likely not great for real world use cases, but good for demonstration/PoC).

```shell
# Apply example HPA and make sure the custom metrics adapter is working as expected
kubectl apply -n gemma -f $BASE/vllm-infgw-hpas.yaml
kubectl get hpa -n gemma 
# Targets "0/10m (avg)" is expected for a server with no traffic. If you still 
# see "<unknown>/10m (avg)" you likely need the stackdriver adapter below

# Describe for more details or try using https://cloud.google.com/kubernetes-engine/docs/how-to/view-horizontalpodautoscaling-events
kubectl describe hpa -n gemma vllm-gemma-3-1b

# Error message indicating missing custom metric adapter
Warning  FailedGetExternalMetric  3s (x6 over 78s)  horizontal-pod-autoscaler  unable to get external metric
gemma/prometheus.googleapis.com|inference_pool_average_kv_cache_utilization|gauge/&LabelSelector{
MatchLabels:map[string]string{metric.labels.name: vllm-gemma-3-1b,},MatchExpressions:[]LabelSelectorRequirement{},}:
unable to fetch metrics from external metrics API: the server could not find the requested resource (get
prometheus.googleapis.com|inference_pool_average_kv_cache_utilization|gauge.external.metrics.k8s.io)

# Fix above error by configuring GKE Custom Metrics Adapter https://cloud.google.com/stackdriver/docs/managed-prometheus/hpa#stackdriver-adapter
gcloud projects add-iam-policy-binding projects/$PROJECT_ID \
  --role roles/monitoring.viewer --condition None \
  --member=principal://iam.googleapis.com/projects/$PROJECT_NUM/locations/global/workloadIdentityPools/$PROJECT_ID.svc.id.goog/subject/ns/custom-metrics/sa/custom-metrics-stackdriver-adapter

kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml

# You should then soon see values when watching the HPA
kubectl get hpa -n gemma -w

# Run a simple load test with 250 workers and 45k requests using https://github.com/rakyll/hey
# Note Hey is very specific about URL being last https://github.com/rakyll/hey/issues/50#issuecomment-374420557
PROMPT="What are the top 5 most popular programming languages? Please be brief."
hey -c 250 -n 45000 -t 60 -m POST -host api.example.com -H "Content-Type: application/json" \
  -d "{ \"model\": \"google/gemma-3-4b-it\", \"max_tokens\": 200, \"prompt\":\"$PROMPT\" }" \
  http://$GW_IP/v1/completions

# Can also use google/gemma-3-1b-it (hard to make scale) or meta-llama/Llama-3.2-3B-Instruct (missing hpa)

# The above hpa watch command will show HPA target replica values or you can watch new pods being created using:
kubectl get pod -n gemma -w

# Load test results should look something like this
Summary:
  Total:	546.8358 secs
  Slowest:	15.5625 secs
  Fastest:	0.1018 secs
  Average:	2.8737 secs
  Requests/sec:	82.2916
  
  Total data:	1078 bytes
  Size/request:	0 bytes

Response time histogram:
  0.102 [1]	|
  1.648 [8159]	|■■■■■■■■■■■■■
  3.194 [25390]	|■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  4.740 [6928]	|■■■■■■■■■■■
  6.286 [1851]	|■■■
  7.832 [871]	|■
  9.378 [1160]	|■■
  10.924 [127]	|
  12.470 [113]	|
  14.016 [92]	|
  15.562 [308]	|

Latency distribution:
  10% in 1.2637 secs
  25% in 1.8223 secs
  50% in 2.3218 secs
  75% in 3.2330 secs
  90% in 4.7480 secs
  95% in 7.0498 secs
  99% in 11.8378 secs

Details (average, fastest, slowest):
  DNS+dialup:	0.0006 secs, 0.1018 secs, 15.5625 secs
  DNS-lookup:	0.0000 secs, 0.0000 secs, 0.0000 secs
  req write:	0.0000 secs, 0.0000 secs, 0.0031 secs
  resp wait:	2.8729 secs, 0.1015 secs, 15.4240 secs
  resp read:	0.0001 secs, 0.0000 secs, 0.0062 secs

Status code distribution:
  [200]	44988 responses
  [429]	11 responses
  [503]	1 responses

# TODO: replace above with a more advanced load test using https://grafana.com/docs/k6/latest/set-up/install-k6/
# MIT licensed examples https://github.com/wizenheimer/periscope/blob/main/scripts/openai-completions-stress.js
# and https://github.com/wizenheimer/periscope/blob/main/scripts/openai-completions.js
```
NOTE: Due to the way these vllm pods download the model on startup it may take 7-10 minutes for new pods to start (1/1 containers ready). If the Hey command finishes before autoscaling occurs you may need to increase the request count or run it multiple times in a loop. In a production environment you would use fully baked pods or sideload models and weights from AI/ML optimized storage like [Hyperdisk ML](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/hyperdisk-ml).

# GKE Inference Gateway and Cloud Monitoring

The GKE Inference Gateway also includes some example monitoring dashboards:

- Cloud Console -> Monitoring -> [Dashboards](https://console.cloud.google.com/monitoring/dashboards) -> View Dashboard Templates
- Search for dashboards: vllm
- Select: vLLM Prometheus Overview ([direct link](https://console.cloud.google.com/monitoring/dashboards/integration/vllm.vllm-prometheus))

Which uses metrics from the **vllm-gemma-3-1b:8000/metrics** endpoint and requires either Managed Prometheus [Automatic Application Monitoring](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-automatic-application-monitoring) or manually configured metric scraping (PodMonitor/ClusterPodMonitor/etc). So if the dashboard is empty make sure automatic application monitoring is enabled for the cluster.

There also is an example dashboard showing details for the Inference Gateway/Pool/Models:
- Search for dashboards: inference
- Select: GKE Inference Gateway Prometheus Overview ([direct link](https://console.cloud.google.com/monitoring/dashboards/integration/gateway-api-inference-extension.inference-extension-prometheus))

TODO: Link to blog post or screenshots of dashboards?

# Google Cloud Armor WAF for GKE Inference Gateway

To configure [Cloud Armor](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources#configure_cloud_armor) Web Application Firewall (WAF) rules on the GKE Inference Gateway, you need to specify **InferencePool** as the **targetRef kind** on the **GCPBackendPolicy** resource instead of the usual Service or ServiceImport. See [./infgw-policy-cloud-armor.yaml](./infgw-policy-cloud-armor.yaml) example for what that looks like. Also because the rules are apply at a Backend Service level, they will not be evaluated for things like RequestRedirect filters.

**NOTE:** The [InferencePool helm chart](https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/9a2667c2853c0883c8d340f25e35b204dc970604/config/charts/inferencepool/templates/gke.yaml) currently includes it's own static GCPBackendPolicy manifest, so you will need to either customize the chart or apply an updated manifest manually using something like:

```shell
kubectl apply -n gemma -f $BASE/infgw-policy-cloud-armor.yaml
```

Expected curl result when WAF rule action is deny-403:

```
< HTTP/1.1 403 Forbidden
< content-type: text/html; charset=UTF-8
< content-length: 134
< x-infgw-selected: infp-gemma3-1b
< date: Thu, 24 Jul 2025 21:47:04 GMT
< via: 1.1 google
< 
* Connection #0 to host api.example.com left intact
<!doctype html><meta charset="utf-8"><meta name=viewport content="width=device-width, initial-scale=1"><title>403</title>403 Forbidden
```

**NOTE:** It currently seems when applying the GCPBackendPolicy to target one InferencePool, the WAF rules will apply to all InferencePools in the Url map. The [GCP Console](https://console.cloud.google.com/net-security/securitypolicies/list) will only show the desired Backend Service, but from my testing the rules applied to all InferencePool instances.

# Advanced Topics

TODO: add details about how EPP picks backends and the options for configuring it

https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/docs/proposals/004-endpoint-picker-protocol

Customize EPP using ENV var?
https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/release-0.4/cmd/epp/runner/runner.go#L271-L272

https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/docs/proposals/0683-epp-architecture-proposal

TODO add lora examples?
https://github.com/cr7258/gateway-api-inference-extension/blob/main/config/manifests/vllm/gpu-deployment.yaml

TODO: add example for https://docs.vllm.ai/en/latest/features/lora.html#serving-lora-adapters

TODO: move shared gateway to it's own namespace? I think this requires ReferenceGrants https://github.com/gbrayut/cloud-examples/blob/main/asm-multi-cluster-failover/httproute-weighted.yaml#L72

TODO: instructions for connecting Gradio to use Inference Gateway? And have a model selector in web UI?

# General Troubleshooting

## Pod Monitoring / Missing Metrics
If the HPA or Dashboard are not working you can try enabling [Target Status](https://cloud.google.com/stackdriver/docs/managed-prometheus/setup-managed#target-status) details in Managed Prometheus to ensure it can access the metrics endpoint on the EPP pod. If you see this error message:

> Last Error:                    Get "http://10.120.2.35:9090/metrics": unable to read authorization credentials: secret default/inference-gateway-sa-metrics-reader-secret not found or forbidden

then double check vllm-infgw-metrics.yaml created the scrape secret, and you may also need to delete/rollout restart the collector pod on any nodes where the epp is running.

## View HTTP Logs

This [example query](https://console.cloud.google.com/logs/query;query=resource.type%3D%22http_external_regional_lb_rule%22%0Aresource.labels.network_name%3D%22gke-vpc%22%0Aresource.labels.region%3D%22us-central1%22
) should show the HTTP logs for an external regional ALB in Log Explorer:

```shell
resource.type="http_external_regional_lb_rule"
resource.labels.network_name="gke-vpc"
resource.labels.region="us-central1"
```

## Force scale-down vllm deployment or adjust HPA values

```shell
# Remove all vllm pods and you should see GPU nodes scale down soon as well
kubectl scale deployment -n gemma vllm-gemma-3-1b --replicas=0
kubectl scale deployment -n gemma vllm-gemma-3-4b --replicas=0

# Or adjust min/max on HPA (requires deployment replica be >= 1 for metric scraping)
kubectl patch hpa vllm-gemma-3-4b -n gemma  --patch '{"spec":{"minReplicas": 2, "maxReplicas": 15}}'

# Note you may also need to adjust the node pool max value or pods may get stuck pending
```

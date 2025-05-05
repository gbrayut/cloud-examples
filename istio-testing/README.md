# Example commands for testing istio/envoy proxy

[whereami](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/tree/main/quickstarts/whereami) makes a good test pod, but for more information (headers, src port, etc) try https://github.com/InAnimaTe/echo-server or https://github.com/mccutchen/go-httpbin

```bash
# See whereami-deploy.yaml for client test pod that deploys into an namespace with sidecar istio-injection
kubectl create ns testing
kubectl label namespace testing istio-injection=enabled istio.io/rev- --overwrite
kubectl apply -f ./whereami-deploy.yaml

# Create 3 target services and pods (no deployments) using different ports and istio-system namespace (which prevents them getting sidecar proxies)
export myport=8080;kubectl run -n istio-system --env="PORT=$myport" --annotations="traffic.sidecar.istio.io/excludeInboundPorts=$myport" --image=docker.io/inanimate/echo-server --port ${myport} --expose echo${myport}

export myport=9090;kubectl run -n istio-system --env="PORT=$myport" --annotations="traffic.sidecar.istio.io/excludeInboundPorts=$myport" --image=docker.io/inanimate/echo-server --port ${myport} --expose echo${myport}

export myport=9999;kubectl run -n istio-system --env="PORT=$myport" --annotations="traffic.sidecar.istio.io/excludeInboundPorts=$myport" --image=docker.io/inanimate/echo-server --port ${myport} --expose echo${myport}

# Can then exec into whereami pod and run curl commands:
kubectl get pod -n istio-system -o wide    # find direct pod IPs for testing
kubectl get svc -n istio-system -o wide    # find cluster IPs for testing
kubectl get pod -n testing -o wide         # find client pod name

kubectl exec -it whereami-5ff4559b5c-l52bs -n testing -- /bin/bash

# Inside the pod, use curl to test. echoserver will reply with details. 
# Using a distinct --local-port makes it easy to see if envoy proxy intercepted
curl -vs --local-port 18080 echo8080.istio-system.svc:8080 | head -n 35

curl -vs --local-port 19090 echo9090.istio-system.svc:9090 | head -n 35

curl -vs --local-port 19999 echo9999.istio-system.svc:9999 | head -n 35

# Can also test against pod IP or cluster IPs
curl -vs 10.1.1.5:8080 | head -n 35
curl -vs 10.1.2.13:9090 | head -n 35
curl -vs 10.1.2.12:9999 | head -n 35
```
See [echoserver-testing.txt](./echoserver-testing.txt) for example output

## istioctl

[istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/#get-proxy-configuration) can be used to see information about envoy sidecar proxy configuration in each pod.
See an example of output in [istioctl-proxy-config.txt](./istioctl-proxy-config.txt).

```bash
# View cluster and other envoy config settings for a pod.namespace
istioctl proxy-config all whereami-758fc65995-62spk.testing

# List log levels for pod
istioctl proxy-config log whereami-758fc65995-62spk.testing
# Update log levels for pod (cannot be used to configure Envoy Access Logs)
istioctl proxy-config log whereami-758fc65995-62spk.testing --level http:info,server:debug,client:debug,router:debug

# Some more useful commands in experimental section (shortcut name x)
istioctl experimental
istioctl experimental revision list
istioctl experimental injector list

# https://istio.io/latest/docs/ops/diagnostic-tools/istioctl-analyze/
istioctl analyze --namespace testing

# These don't seem to work with Anthos Service Mesh
istioctl x describe pod whereami-758fc65995-62spk.testing
```

## iptables ingress / egress rules

Use annotations to [exclude traffic](https://cloud.google.com/service-mesh/docs/security/anthos-service-mesh-security-best-practices?hl=en#securely-handle-anthos-service-mesh-policy-exceptions) from the mesh. To verify it is working, see the following examples based on above testing pods

* [Init logs](./iptables-init-logs.txt) either via istio-init container or istio-cni-node daemonset
* [Direct inspection](./iptable-inspect-rules.txt) via SSH into node and entering PID/Network namespace

## misc

ASM guide https://cloud.google.com/service-mesh/docs/troubleshooting/troubleshoot-intro

Istio's guide https://github.com/istio/istio/wiki/Troubleshooting-Istio#diagnostics

```
# Use --raw to proxy request from master node to specific service/port
kubect get --raw /api/v1/namespaces/istio-system/services/https:istiod:https-webhook/proxy/inject -v4

# Another example for whereami svc in testing namespace
kubect get --raw /api/v1/namespaces/testing/services/http:whereami:http/proxy/ -v4
{
  "cluster_name": "gke-central", 
  "host_header": "35.193.71.107", 
  "pod_name": "whereami-758fc65995-62spk", 
  "pod_name_emoji": "0️⃣", 
  "project_id": "myproject", 
  "timestamp": "2022-06-14T01:51:27", 
  "zone": "us-central1-b"
}

# If the above gets a timeout, it may be because only 443 is allowed by default.
# Firewall rule (target-tags and source-ranges should match similar gke master rules)
gcloud compute firewall-rules create gke-master-webhook-port \
  --network=default \
  --action=allow \
  --direction=ingress \
  --target-tags=gke-gke-central-24f2b9d4-node \
  --source-ranges=172.16.0.16/28 \
  --rules=tcp:8080,tcp:9090
```

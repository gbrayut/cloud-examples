# GKE Agent Sandbox
[GKE Agent Sandbox](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/machine-learning/agent-sandbox) is based on the open-source [Agent Sandbox project](https://agent-sandbox.sigs.k8s.io/) and helps you manage isolated, stateful, and single-replica workloads in Kubernetes clusters. It is optimized for use cases like AI agent runtimes that need to generate and execute untrusted code in a disposable (single-use) environment. Follow the [setup instructions and pod requirements/limitations](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/how-install-agent-sandbox) to get started using Agent Sandbox:

```shell
# Create a new cluster or update an existing cluster using --enable-agent-sandbox

# Then add a node pool using the gvisor sandbox
gcloud container node-pools create "my-gvisor-sandbox" --cluster "my-cluster" --project "my-project" \
  --region "us-central1" --machine-type "e2-standard-8" --image-type "cos_containerd" --disk-type "pd-standard" \
  --disk-size "100" --num-nodes "1" --enable-autoscaling --min-nodes=0 --max-nodes=3 \
  --enable-autoupgrade --enable-autorepair --max-surge-upgrade "1" \
  --max-unavailable-upgrade "0" --sandbox type=gvisor

# Create the namespace used by the examples below
kubectl create ns test-sandbox

# Apply examples (see bottom of each yaml file for testing/validation commands)
BASE=https://github.com/gbrayut/cloud-examples/raw/refs/heads/main
kubectl apply -f ${BASE}/gke-agent-sandbox/agentsandbox-example.yaml
kubectl apply -f ${BASE}/gke-agent-sandbox/agentsandbox-k8s-secrets.yaml
kubectl apply -f ${BASE}/gke-agent-sandbox/agentsandbox-projected-volumes.yaml
kubectl apply -f ${BASE}/gke-agent-sandbox/agentsandbox-tls-gke-mwlid.yaml
# This example will require customization to fit your environment
kubectl apply -f ${BASE}/gke-agent-sandbox/agentsandbox-secret-manager.yaml
```
More end-to-end examples can be found in the [official GKE docs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox) or in the upstream [Agent Sandbox](https://agent-sandbox.sigs.k8s.io/docs/use-cases/examples/) project website. See also the alternate path for using [Kata Containers](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/kata-gke-sandbox) with nested virtualization instead of [gVisor](https://gvisor.dev/).

## Basic Agent Sandbox Examples
The [agentsandbox-example.yaml](./agentsandbox-example.yaml) manifest shows how to create a basic standalone **Sandbox** on GKE. See the [docs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/machine-learning/agent-sandbox-storage) for recommended storage options for different types of workloads. Also the [GCSFuse Sandbox examples](../gke-storage-misc/gcsfuse.md#gke-sandbox-and-gcsfuse-volumes) show how you can use **SandboxTemplate, SandboxWarmPool, and SandboxClaim** resources to improve the sandbox startup time by pre-provisioning nodes and pods in the cluster.

## Managing Secrets in Sandbox Workloads
For workloads that need access to common secrets (not unique to the agent instance), [agentsandbox-k8s-secrets.yaml](./agentsandbox-k8s-secrets.yaml) shows how to use native Kubernetes Secrets and [agentsandbox-secret-manager.yaml](./agentsandbox-secret-manager.yaml) shows how to use [GKE Secret Manager CSI](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component) integration for centralized management. The [agentsandbox-projected-volumes.yaml](./agentsandbox-projected-volumes.yaml) example shows how to use [Projected Volumes](https://kubernetes.io/docs/concepts/storage/projected-volumes/) with native secrets, Downward API, or ConfigMap values. Note that GKE Sandbox **does not** allow using Projected Volumes for service account tokens or certificates.

When using Secret Manager for centralized access, the cluster will need the add-on enabled using `--enable-secret-manager` and the pod's KSA will need the correct IAM permissions. Also to enable [automatic rotation/updates](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component#configure-auto-rotation) of secret values use the `--enable-secret-manager-rotation --secret-manager-rotation-interval=300s` options for a 5 minute refresh interval. And you of course will want to monitor your [Secret Manager](https://docs.cloud.google.com/secret-manager/quotas) quota usage.

## mTLS Certificates for Sandbox Workloads
The [limitations section for GKE Sandbox pods](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/sandbox-pods) and the Cloud Service Mesh documentation both state that workloads using GKE Sandbox are not supported by CSM. Due to how gVisor implements the sandbox it is also likely that other service mesh providers (Istio, Linkerd, Cilium, etc) will not work if they require using eBPF or iptables to hijack pod ingress and egress traffic. For these and other reasons your sandbox workloads often will not be included as part of your existing application service mesh.

For basic TLS or mTLS you can use [Managed Workload Identity](https://docs.cloud.google.com/iam/docs/managed-workload-identity) (MWLID) to automatically provision [SPIFFE](https://spiffe.io/) based X.509 certificates for pods, VMs, and other parts of GCP infrastructure. A certificate using the pod's Kubernetes Service Account (KSA) identity can then be used directly in your application code or via a custom sidecar (ghostunnel, envoy, nginx, etc). The workload certificates are issued by a Default CA (fully managed by Google) or using a custom Certificate Authority Service (Private CA), and are automatically rotated around halfway through their 24-hour expiration window. See the GKE [MWLID Setup Instructions](https://docs.cloud.google.com/iam/docs/create-managed-workload-identities-gke) and the [agentsandbox-tls-gke-mwlid.yaml](./agentsandbox-tls-gke-mwlid.yaml) example for more details on how to configure workload certificates. This is the same component used for [Google Enterprise Agent Identity](https://docs.cloud.google.com/iam/docs/agent-identity-overview), which in the future will also be supported for agents running in GKE.

Be aware that TLS server connections using certificates with `spiffe://PROJECT_NAME.svc.id.goog/ns/NAMESPACE_NAME/sa/KSA_NAME` style subjects may require client-side changes since the server certificate will not match the DNS hostname or IP address used to dial the connection. Instead of direct pod connections, Agent Sandbox often uses the [Sandbox Router](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox#deploy_the_sandbox_router). If HTTPS connections using correct DNS Hostnames or IP Addresses is required, the [OSS cert-manager project](https://cert-manager.io/) is likely the best option (see [gke cert-manager examples](../gke-cert-manager/) for more details).

## Sandbox Instance-Specific Customizations
Note that all of the above are based on the Pod's KSA Identity and that when using generic sandbox warm pools (Python-Sandbox, Java-Sandbox, etc) those identities are shared and defined well before the sandbox is pulled out of the pool. The workload-level identity will often not represent specific agent instances or their assigned users and should mainly be used for accessing shared/common data.

ADK and other frameworks can [help create and initialize the sandbox](https://agent-sandbox.sigs.k8s.io/docs/use-cases/code-execution/) and can include an externally generated agent session-specific identity (like a short-lived SPIFFE X.509 certificate or JWT) as part of that initialization along with other session-specific files or environment variables.

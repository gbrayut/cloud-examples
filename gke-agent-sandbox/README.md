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

# Apply examples:
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
The [agentsandbox-example.yaml](./agentsandbox-example.yaml) manifest shows how to create a basic standalone **Sandbox** on GKE. See the [docs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/machine-learning/agent-sandbox-storage) for recommended storage options for different types of workloads. Also the [GCSFuse examples](https://github.com/gbrayut/cloud-examples/blob/main/gke-storage-misc/gcsfuse.md#gke-sandbox-and-gcsfuse-volumes) show how you can use **SandboxTemplate, SandboxWarmPool, and SandboxClaim** resources to improve the sandbox startup time by pre-provisioning nodes and pods in the cluster.

## Managing Secrets in Sandbox Workloads
For workloads that need access to common secrets (not unique to the agent instance), [agentsandbox-k8s-secrets.yaml](./agentsandbox-k8s-secrets.yaml) shows how to use native Kubernetes Secrets and [agentsandbox-secret-manager.yaml](./agentsandbox-secret-manager.yaml) shows how to use [GKE Secret Manager CSI](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component) integration for centralized management. The [agentsandbox-projected-volumes.yaml](./agentsandbox-projected-volumes.yaml) example shows how to use [Projected Volumes](https://kubernetes.io/docs/concepts/storage/projected-volumes/) with native secrets, Downward API, or ConfigMap values. Note that GKE Sandbox **does not** allow using Projected Volumes for service account tokens or certificates.

When using Secret Manager for centralized access, the cluster will need the add-on enabled using `--enable-secret-manager` and the pod's KSA will need the correct IAM permissions. Also to enable [automatic rotation/updates](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component#configure-auto-rotation) of secret values use the `--enable-secret-manager-rotation --secret-manager-rotation-interval=300s` options for a 5 minute refresh interval. And you of course will want to monitor your [Secret Manager](https://docs.cloud.google.com/secret-manager/quotas) quota usage.

## mTLS Certificates for Sandbox Workloads
The [limitations for GKE Sandbox pods](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/sandbox-pods) state that Cloud Service Mesh is not supported in Autopilot clusters. It is also likely that due to how gVisor implements the sandbox you may also have difficulty trying to use other service mesh providers. For basic mTLS you can however use [Managed Workload Identity](https://docs.cloud.google.com/iam/docs/managed-workload-identity) to provision X.509 certificates for sandbox pods based on their Kubernetes Service Account (KSA) for use in your application or via a custom sidecar. See the [MWLID Setup Instructions](https://docs.cloud.google.com/iam/docs/create-managed-workload-identities-gke) and the [agentsandbox-tls-gke-mwlid.yaml](./agentsandbox-tls-gke-mwlid.yaml) for more details. This is the same component used for [Google Cloud Agent Identity](https://docs.cloud.google.com/iam/docs/agent-identity-overview) in Gemini Enterprise, which in the future will be supported for agents running in GKE as well.

## Sandbox Instance-Specific Customizations
Note that all of the above are based on the Pod's KSA Identity and that when using generic sandbox warm pools (Python-Sandbox, Java-Sandbox, etc) those identities are shared and defined well before the sandbox is pulled out of the pool. The workload level identity will often not represent specific agent instances or their assigned users and should mainly be used for accessing shared/common data.

ADK and other frameworks can [help create and initialize the sandbox](https://agent-sandbox.sigs.k8s.io/docs/use-cases/code-execution/) and often will include an externally generated agent session-specific identity (like a short lived SPIFFE X.509 certificate or JWT) as part of that initialization along with other session-specific files or environmental values.


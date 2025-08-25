# GKE Multi Instance GPU workloads

GKE [multi-instance GPUs](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus-multi#standard) allow you to partition an NVIDIA A100, H100, H200, or B200 to share a single GPU across multiple containers on Google Kubernetes Engine. This setup follows the [Gemma on GKE with vLLM](https://cloud.google.com/kubernetes-engine/docs/tutorials/serve-gemma-gpu-vllm) guide, requires a [Hugging Face token](https://huggingface.co/docs/hub/security-tokens), and your HF user account **must accept** the [Gemma license](https://huggingface.co/google/gemma-3-1b-it).

```shell
# See which zones have accelerators
gcloud compute accelerator-types list --filter="name:(nvidia-tesla-a100 nvidia-a100-80gb)" --sort-by=name,zone
NAME               ZONE               DESCRIPTION
nvidia-a100-80gb   us-central1-a      NVIDIA A100 80GB
nvidia-a100-80gb   us-central1-c      NVIDIA A100 80GB
nvidia-a100-80gb   us-east4-c         NVIDIA A100 80GB
nvidia-a100-80gb   us-east5-a         NVIDIA A100 80GB
nvidia-a100-80gb   us-east5-b         NVIDIA A100 80GB
nvidia-a100-80gb   us-east7-a         NVIDIA A100 80GB
nvidia-tesla-a100  us-central1-a      NVIDIA A100 40GB
nvidia-tesla-a100  us-central1-b      NVIDIA A100 40GB
nvidia-tesla-a100  us-central1-c      NVIDIA A100 40GB
nvidia-tesla-a100  us-central1-f      NVIDIA A100 40GB
nvidia-tesla-a100  us-east1-a         NVIDIA A100 40GB
nvidia-tesla-a100  us-east1-b         NVIDIA A100 40GB
nvidia-tesla-a100  us-east7-b         NVIDIA A100 40GB
nvidia-tesla-a100  us-west1-b         NVIDIA A100 40GB
nvidia-tesla-a100  us-west3-b         NVIDIA A100 40GB
nvidia-tesla-a100  us-west4-b         NVIDIA A100 40GB

# Add multi-instance gpu node pool to a cluster https://cloud.google.com/kubernetes-engine/docs/how-to/gpus-multi#install-driver
gcloud container node-pools create multi-a2-1g-5gb \
    --cluster=gke-iowa --location=us-central1 --machine-type=a2-highgpu-1g \
    --accelerator="type=nvidia-tesla-a100,count=1,gpu-partition-size=1g.5gb,gpu-driver-version=latest" \
    --enable-autoscaling  --num-nodes=1 --min-nodes=1 --max-nodes=1  \
    --location-policy=ANY  --reservation-affinity=none --node-locations=us-central1-f

# Create a Kubernetes secret for Hugging Face credentials
HF_TOKEN=hf_naf...REDACTED
kubectl create ns gemma
kubectl create secret generic hf-secret -n gemma --from-literal=hf_api_token=${HF_TOKEN}
```

# Gemma 3 1B-it using vLLM

Gemma 3 1B model is small enough for inference using the 5GB of GPU Memory in a `cloud.google.com/gke-gpu-partition-size: 1g.5gb` partition and will allow you to run up to 7 replicas on one a2-highgpu-1g node. The [vllm-gemma3-1b.yaml](./vllm-gemma3-1b.yaml) deployment is a modified version of the [GKE Inference Gateway](../gke-ai-infgw/) example as it required tuning the resources to fit multiple replica on the node and setting `--gpu-memory-utilization=0.86` to avoid reserving too much GPU memory for caching. The [gradio.yaml](../gke-ai-infgw/gradio.yaml) manifest creates a basic chat web UI that uses the Gemma 1B vllm deployment via the Kubernetes service.

This should not be considered a production ready deployment as you likely will want to use fully baked container images (vs downloading from HF) and tune the values for HPA/HealthChecks/Timeouts/Probes/etc.

```shell
BASE=https://raw.githubusercontent.com/gbrayut/cloud-examples/refs/heads/main/gke-ai-misc   # Or use local path to cloned repo

# Create deployment, usually takes 5-10 minutes to become ready
kubectl apply -n gemma -f $BASE/vllm-gemma3-1b.yaml
kubectl wait -n gemma --for=condition=Available --timeout=1800s deployment/vllm-gemma-3-1b
# can also follow logs for troubleshooting
kubectl logs -n gemma deploy/vllm-gemma-3-1b -f

# Create gradio deployment for testing chat completions (deployment uses vllm-gemma-3-1b dns service)
kubectl apply -n gemma -f $BASE/../gke-ai-infgw/gradio.yaml
kubectl get svc,pod -n gemma
kubectl port-forward -n gemma service/gradio 8080:8080
# Then connect to chat server using http://localhost:8080 (best to use prompts instructing llm to be brief)

# Testing vllm server directly using curl
curl -s http://localhost:8000/v1/completions   -H "Content-Type: application/json"   -d '{
"model": "google/gemma-3-1b-it",
"prompt": "What are the top 5 most popular programming languages? Please be brief.",
"max_tokens": 200
  }' | jq .

# After confirming one pod works, can scale deployment up to 7 replicas to fill a node
kubectl scale deployment -n gemma vllm-gemma-3-1b --replicas=7
# Check pod status and they should all be running after 5-10 minutes. Any pending pods are 
# waiting for new nodes so they can be scheduled (see kubectl describe -n gemma podvllm-gemma-3-1b-......-...)
kubectl get pods -n gemma -o wide
NAME                               READY   STATUS    RESTARTS   AGE     IP            NODE
vllm-gemma-3-1b-6fd5799bb4-4vtgt   1/1     Running   0          5m33s   10.120.1.33   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-9lsrb   1/1     Running   0          5m33s   10.120.1.34   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-d5t99   1/1     Running   0          5m33s   10.120.1.32   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-hp5k9   0/1     Running   0          5m33s   10.120.1.37   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-jq5x5   1/1     Running   0          5m33s   10.120.1.35   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-mnmc7   0/1     Running   0          5m33s   10.120.1.36   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-nc6tb   1/1     Running   0          56m     10.120.1.26   gke-gke-iowa-multi-a2-1g-5gb-4ebe434e-wmft
vllm-gemma-3-1b-6fd5799bb4-rp879   0/1     Pending   0          4m54s   <none>        <none>                                    
```

# Troubleshooting

If you see this error messages in the logs, try increasing the `--gpu_memory_utilization` value:

```log
INFO 08-25 09:12:34 [gpu_worker.py:276] Available KV cache memory: -2.16 GiB
ValueError: No available memory for the cache blocks. Try increasing `gpu_memory_utilization` when initializing the engine.
```

If you see CUDACachingAllocator error messages in the logs, you ran out of GPU memory and need to decrease the `--gpu_memory_utilization` value:

```log
(EngineCore_0 pid=72) INFO 08-25 09:39:57 [gpu_model_runner.py:2007] Model loading took 1.9147 GiB and 19.421348 seconds
(EngineCore_0 pid=72) INFO 08-25 09:42:20 [gpu_worker.py:276] Available KV cache memory: 1.40 GiB
(EngineCore_0 pid=72) WARNING 08-25 09:42:20 [kv_cache_utils.py:971] Add 2 padding layers, may waste at most 9.09% KV cache memory
(EngineCore_0 pid=72) INFO 08-25 09:42:20 [kv_cache_utils.py:1013] GPU KV cache size: 52,608 tokens
(EngineCore_0 pid=72) INFO 08-25 09:42:20 [kv_cache_utils.py:1017] Maximum concurrency for 32,768 tokens per request: 7.64x
(EngineCore_0 pid=72) INFO 08-25 09:42:24 [gpu_model_runner.py:2708] Graph capturing finished in 4 secs, took 0.39 GiB
(EngineCore_0 pid=72) ERROR 08-25 09:42:24 [core.py:700] EngineCore failed to start.
(EngineCore_0 pid=72) ERROR 08-25 09:42:24 [core.py:700] RuntimeError: NVML_SUCCESS == r INTERNAL ASSERT FAILED at "/pytorch/c10/cuda/CUDACachingAllocator.cpp":1016, please report a bug to PyTorch. 
(EngineCore_0 pid=72) RuntimeError: NVML_SUCCESS == r INTERNAL ASSERT FAILED at "/pytorch/c10/cuda/CUDACachingAllocator.cpp":1016, please report a bug to PyTorch.
```

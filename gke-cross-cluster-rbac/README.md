# Using WIF for GKE Cross Cluster Access

[Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) allows granting IAM permissions [directly](https://cloud.google.com/blog/products/identity-security/make-iam-for-gke-easier-to-use-with-workload-identity-federation) to a pod's Kubernetes Service Account (KSA) and using those strong identities across GCP services/projects/organizations or even in hybrid/multi-cloud environments. The following examples will show how to use KSA tokens and WIF to allow local or cross cluster RBAC to the Kubernetes API.

**Note:** To access a remote cluster you should ideally use the [GKE DNS-based endpoint](https://cloud.google.com/blog/products/containers-kubernetes/new-dns-based-endpoint-for-the-gke-control-plane) as it can follow the same public or private routing you have likely already configured for accessing any other Google Cloud APIs. However you can also use a public or private GKE IP endpoint assuming your client IP is in the authorized networks and has "line-of-sight" routing to the target address. Also routing to private IP endpoints may require a [bastion](https://docs.cloud.google.com/kubernetes-engine/docs/tutorials/private-cluster-bastion) or proxy server in many environments, which is why the DNS Endpoint is preferred.

# Local Kube API access

The [01-test-cloudsdk.yaml](./01-test-cloudsdk.yaml) manifest configures a new **test-cloudsdk** namespace with all the required resources (configmap, ksa, deployment, and rolebinding) and applications (gcloud, kubectl, and curl). The rolebinding grants the local **gcloud-ksa** and the WIF equivalent user the [Kubernetes view](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles) permission to the local namespace for quick testing to confirm everything is configured as expected. This should not require any additional GCP IAM rolebindings because the `KUBECONFIG=/root/cfg/kubeconfig` env variable points directly to the `server: https://kubernetes.default.svc.cluster.local` internal service.

```shell
# Create test-cloudsdk resources on the client gke cluster
kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-cross-cluster-rbac/01-test-cloudsdk.yaml

# Exec into the pod and then run the below test commands
kubectl exec -it -n test-cloudsdk deploy/google-cloud-cli -- /bin/bash
root@google-cloud-cli-677cc94948-8vbv8:/#

# ls /root/cfg/   
kubeconfig  token

# kubectl get pods
NAME                                READY   STATUS    RESTARTS   AGE
google-cloud-cli-5c6ddfb4fc-brdm9   1/1     Running   0          6m27s

# kubectl get pods --context local-adc
NAME                                READY   STATUS    RESTARTS   AGE
google-cloud-cli-5c6ddfb4fc-brdm9   1/1     Running   0          6m43s

# If local-adc shows errors then either edit the ksa-k8s-read-access rolebinding or create a new one
Error from server (Forbidden): pods is forbidden: 
  User "serviceAccount:my-project.svc.id.goog[test-cloudsdk/gcloud-ksa]" cannot list 
  resource "pods" in API group "" in the namespace "test-cloudsdk": requires one of 
  ["container.pods.list"] permission(s).

# Fix ADC permissions by applying the correct user rolebinding to the local cluster:
kubectl create rolebinding ksa-myproject-read-access -n test-cloudsdk --clusterrole=view \
  --user="serviceAccount:my-project.svc.id.goog[test-cloudsdk/gcloud-ksa]"

# Can also make raw API calls using the various tokens (no config files required):
KSATOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
PROJECTEDTOKEN=$(cat /root/cfg/token)
ADCTOKEN=$(gcloud auth print-access-token)
# Use tokens with raw REST API equivalent of kubectl get pods
curl -kv --header "Authorization: Bearer $KSATOKEN" https://kubernetes.default.svc.cluster.local/api/v1/namespaces/test-cloudsdk/pods
```

# View user attributes

You can use the [whoami](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_whoami/) command to see more details about the user. These values are extracted from the token or certificate and usually would be the same when used to authenticate to a remote GKE cluster:

```shell
# kubectl auth whoami
ATTRIBUTE                                           VALUE
Username                                            system:serviceaccount:test-cloudsdk:gcloud-ksa
UID                                                 a0869f5a-462a-4a54-a984-e08009a3cbe2
Groups                                              [system:serviceaccounts system:serviceaccounts:test-cloudsdk system:authenticated]
Extra: authentication.kubernetes.io/credential-id   [JTI=016222e9-ce4a-4109-bab6-cfe19f487e33]
Extra: authentication.kubernetes.io/node-name       [gke-gke-iowa-default-pool-369f4c0b-6t2h]
Extra: authentication.kubernetes.io/node-uid        [716de081-1de9-407e-8e63-1cad5211bbf7]
Extra: authentication.kubernetes.io/pod-name        [google-cloud-cli-5c6ddfb4fc-brdm9]
Extra: authentication.kubernetes.io/pod-uid         [32f42699-5592-4073-83db-2fa0ce433aba]

# kubectl auth whoami --context local-adc
ATTRIBUTE                                VALUE
Username                                 serviceAccount:gregbray-vpc.svc.id.goog[test-cloudsdk/gcloud-ksa]
Groups                                   [principalSet://iam.googleapis.com/gregbray-vpc.svc.id.goog/group//allAuthenticatedUsers/ system:authenticated]
Extra: iam.gke.io/user-assertion         [AHOUAc1u....omitted....6ghIPaoRPkwg==]
Extra: user-assertion.cloud.google.com   [AHOUAc3Q....omitted....bo/Uht76MgMzo=]
```

# Connect to remote GKE cluster using WIF for GKE

The kubeconfig file from above also includes a remote GKE cluster, which in this case is the DNS endpoint for an Autopilot GKE cluster in another project or organization. To allow access we will need to grant the required [GCP IAM Permissions](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/iam) for get-credentials and connecting to the DNS Endpoint, along with creating a Kubernetes rolebinding for the desired namespaces (in this case just default).

```shell
# GCP IAM policy to allow pod's KSA to connect to target project's GKE clusters
gcloud projects add-iam-policy-binding gregbray-alt \
  --role roles/container.clusterViewer --condition None \
  --member=principal://iam.googleapis.com/projects/gregbray-vpc/locations/global/workloadIdentityPools/gregbray-vpc.svc.id.goog/subject/ns/test-cloudsdk/sa/gcloud-ksa

# GKE RBAC to allow Username attribute access to default namespace (same as ksa-k8s-read-access but without local ksa subject)
# Again using built in view ClusterRole but usually you would create a custom Role resource
kubectl create rolebinding remote-ksa-read-access -n default --clusterrole=view \
  --user="serviceAccount:gregbray-vpc.svc.id.goog[test-cloudsdk/gcloud-ksa]"

# Test from client pod using kubeconfig in configmap (assuming you fix the target server value)
kubectl exec -it -n test-cloudsdk deploy/google-cloud-cli -- \
  kubectl get pods --context ap1-us-west1 -o wide
NAME            READY   STATUS    RESTARTS   AGE   IP           NODE                         
ap-1-whereami   1/1     Running   0          20s   10.75.0.84   gk3-ap-1-pool-1-ab76f3cd-5m5p

# Or if you exec into the pod you can then generate a new kubeconfig using gcloud get-credentials
export KUBECONFIG=~/.kube/config    # use default location since configmap is read only
gcloud container clusters get-credentials ap-1 --project gregbray-alt \
  --region us-west1 \
  --no-dns-endpoint     # Uses public IP endpoint with embedded certificate-authority-data
kubectl config view
kubectl get pods
```

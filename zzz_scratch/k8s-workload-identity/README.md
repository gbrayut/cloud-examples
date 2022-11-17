# Cluster and Fleet Workload Identity

## Overview

Workload Identity allows workloads in your GKE clusters to impersonate Identity and Access Management (IAM) service accounts to access Google Cloud services.

You can create one workload identity pool for each Google Cloud project, with the format `PROJECT_ID.svc.id.goog`, and cluster

Workload Identity replaces the need to use Metadata concealment. The sensitive metadata protected by metadata concealment is also protected by Workload Identity.

When GKE enables the GKE metadata server on a node pool, Pods can no longer access the Compute Engine metadata server. Instead, the GKE metadata server intercepts requests made from these pods to metadata endpoints, with the exception of Pods running on the host network.



https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity

https://cloud.google.com/anthos/fleet-management/docs/use-workload-identity

https://hilliao.medium.com/google-recommended-security-iam-practice-on-gke-a58ddfb605a3




## Test WI by listing storage buckets
gcloud projects add-iam-policy-binding gregbray-repo  --member="serviceAccount:gregbray-vpc.svc.id.goog[testing/default]"  --role="roles/storage.admin"
gcloud --verbosity=debug alpha storage ls --project gregbray-repo
gsutil ls -p gregbray-repo

#NOTE: gcloud and gsutil don't work for testing ADC method used by fleet WI. Should test using compute or storage rest api
curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" https://compute.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-a/instances

curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" "https://storage.googleapis.com/storage/v1/b?project=gregbray-repo&alt=json&fields=items%2Fname"

# Cluster and Fleet Workload Identity

## Overview

Workload Identity allows workloads in your GKE clusters to impersonate Identity and Access Management (IAM) service accounts to access Google Cloud services.

You can create one workload identity pool for each Google Cloud project, with the format `PROJECT_ID.svc.id.goog`, and cluster

Workload Identity replaces the need to use Metadata concealment. The sensitive metadata protected by metadata concealment is also protected by Workload Identity.

When GKE enables the GKE metadata server on a node pool, Pods can no longer access the Compute Engine metadata server. Instead, the GKE metadata server intercepts requests made from these pods to metadata endpoints, with the exception of Pods running on the host network.



https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity

https://cloud.google.com/anthos/fleet-management/docs/use-workload-identity
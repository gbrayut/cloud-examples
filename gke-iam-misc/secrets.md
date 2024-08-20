# Grant access to Secret Manager via Workload Identity Federation for GKE

Create new entries in Secret Manager:
```shell
# https://cloud.google.com/sdk/gcloud/reference/secrets
gcloud secrets create test-secret --data-file=<(echo -n hunter2) \
    --labels="mylabel=test" --set-annotations="myannotation=test"

# https://cloud.google.com/sdk/gcloud/reference/secrets/versions/access
gcloud secrets versions access --secret test-secret latest 

gcloud secrets create another --data-file=<(echo -n hunter1) \
    --labels="mylabel=test" --set-annotations="myannotation=test"
```


Then configure permissions below and apply a [test workload](./secrets-pod.yaml) using [GKE Secrets Manager CSI](https://cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component) integration.

```shell
PROJECT_ID="gregbray-vpc"
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
PRINCIPAL_BASE="iam.googleapis.com/projects/$PROJECT_NUM/locations/global/workloadIdentityPools/$PROJECT_ID.svc.id.goog"

# Use this to allow the specific KSA access to the test-secret entry
gcloud secrets add-iam-policy-binding test-secret \
    --role=roles/secretmanager.secretAccessor \
    --member="principal://$PRINCIPAL_BASE/subject/ns/test-secrets/sa/gcloud-ksa"

# Confirm values are mounted into pod filesystem
kubectl exec -it -n test-secrets gcloud-bare-pod -- /bin/bash -c 'grep . /var/secrets/*.txt'

# Can also grant access to all KSA in the test-secrets namespace using:
gcloud secrets add-iam-policy-binding test-secret \
    --role=roles/secretmanager.secretAccessor \
    --member="principalSet://$PRINCIPAL_BASE/namespace/test-secrets"

# Or grant access to all KSA in a specific cluster
# See https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity#kubernetes-resources-iam-policies
CLUSTER_ID="https://container.googleapis.com/v1/projects/$PROJECT_ID/locations/us-west1/clusters/gke-oregon"
gcloud secrets add-iam-policy-binding test-secret \
  --role=roles/secretmanager.secretAccessor \
  --member="principalSet://$PRINCIPAL_BASE/kubernetes.cluster/$CLUSTER_ID"

# Or grant access to all KSA for a specific fleet/Workload Identity Pool
# see https://cloud.google.com/iam/docs/principal-identifiers for v1 and v2 versions of all workload pool identities
gcloud secrets add-iam-policy-binding test-secret \
  --role=roles/secretmanager.secretAccessor \
  --member="group:$PROJECT_ID.svc.id.goog:/allAuthenticatedUsers/"

# v2 "principalSet://$PRINCIPAL_BASE/*" should work if it was a non-gke identity pool, but gives an error for GKE WI Pools:
# ERROR: (gcloud.secrets.add-iam-policy-binding) Status code: 400. Identity Pool does not exist (projects/503076227230/locations/global/workloadIdentityPools/gregbray-vpc.svc.id.goog). Please check that you specified a valid resource name as returned in the `name` attribute in the configuration API..
```

## IAM Conditions

Instead of granting permissions on individual secrets, you can instead use project/folder/organization level [IAM Conditions](https://cloud.google.com/iam/docs/conditions-overview) for [resource attributes](https://cloud.google.com/iam/docs/conditions-attribute-reference#resource).

Note: Not sure if you can use attribute/labels/tags in the conditions, but I suspect it only supports the resource name since that is the only parameter in the project.secrets.versions [access method](https://cloud.google.com/secret-manager/docs/reference/rest/v1/projects.secrets.versions/access).

Note: [Principal attributes](https://cloud.google.com/iam/docs/conditions-attribute-reference#principals) can only be used when creating [Principal Access Boundary Policies](https://cloud.google.com/iam/docs/principal-access-boundary-policies). You cannot dynamically evaluate rules based on the principal or any other GKE identity attributes besides the ones listed above.

```shell

# Grant namespace access to multiple SecretVersion based on target resource name
# See https://cloud.google.com/iam/docs/conditions-resource-attributes#resource-name
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --role=roles/secretmanager.secretAccessor \
  --member="principalSet://$PRINCIPAL_BASE/namespace/test-secrets" \
  --condition-from-file=<(cat <<- END
---
title: allow_gke_test_secrets
description: Restrict to specific resource names
expression: |-
  resource.name.startsWith('projects/$PROJECT_NUM/secrets/test-') ||
  resource.name.endsWith('/secrets/another/versions/latest')
END
)
```

TODO: Add non-file example using --condition="expression=resource.blah,title=allow_blah"

TODO: See if Secret Manager supports https://cloud.google.com/iam/docs/conditions-resource-attributes#resource-tags as that would be a best practice if it works

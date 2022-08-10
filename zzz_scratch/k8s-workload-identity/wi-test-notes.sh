# Create a new Google Service Account (GSA) and allow a Kubernetes Service Account (KSA) to generate tokens for it via Workload Identity
gcloud iam service-accounts create test-sa --project=my-project
gcloud iam service-accounts add-iam-policy-binding test-sa@my-project.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:WI_PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]"

# After applying wi-test.yaml file, verify metadata server returns correct service account details
$ kubectl exec -it workload-identity-test --namespace testing -- curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/?recursive=true
{
  "aliases": [
    "default"
  ],
  "email": "WI_PROJECT_ID.svc.id.goog",
  "scopes": [
    "https://www.googleapis.com/auth/cloud-platform"
  ]
}

# Or if you set iam.gke.io/gcp-service-account annotation on ServiceAccount you would see the target GSA value, like:
  "email": "test-sa@my-project.iam.gserviceaccount.com",

# However if the Google Service Account doesn't exist you will get an error when you try and generate a token
$ kubectl exec -it workload-identity-test --namespace testing -- curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
Unable to generate access token; IAM returned 404 Not Found: Requested entity was not found.
# Also if the the namespace's Kubernetes Service Account does not have workloadIdentityUser permissions you will also get an error (see add-iam-policy-binding above to fix)
$ kubectl exec -it workload-identity-test --namespace testing -- curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
Unable to generate access token; IAM returned 403 Forbidden: The caller does not have permission
This error could be caused by a missing IAM policy binding on the target IAM service account.
For more information, refer to the Workload Identity documentation:
	https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#authenticating_to

# If it is working correctly you should be able to generate an access token (similar to using gcloud auth print-access-token):
$ kubectl exec -it workload-identity-test --namespace testing -- curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq
{
  "access_token": "...omitted...",
  "expires_in": 3578,
  "token_type": "Bearer"
}

# You can also validate the token
TOKEN=$(kubectl exec -it workload-identity-test --namespace testing -- gcloud auth application-default print-access-token)
curl -H "Content-Type: application/x-www-form-urlencoded" -d "access_token=$TOKEN" https://www.googleapis.com/oauth2/v1/tokeninfo
{
  "issued_to": "108222364016549509974",
  "audience": "108222364016549509974",
  "scope": "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/cloud-platform",
  "expires_in": 2395,
  "email": "test-sa@my-project.iam.gserviceaccount.com",
  "verified_email": true,
  "access_type": "online"
}


# If you want to test having non-WI workloads, add another nodepool that uses GCE_METADATA instead of GKE_METADATA
gcloud beta container --project "gregbray-vpc" node-pools create "secondary" --cluster "gke-iowa" --region "us-central1" \
  --machine-type "e2-standard-4" --image-type "UBUNTU_CONTAINERD" --disk-type "pd-standard" --disk-size "100" \
  --num-nodes "1" --enable-autoscaling --min-nodes=0 --max-nodes=3 --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 --max-pods-per-node "110" --node-locations "us-central1-c" \
  --workload-metadata GCE_METADATA --node-taints=testing.local=tainted:NoSchedule

# Now when testing you should see the project's default compute service account (or whatever was specified via --service-account)
$ kubectl exec -it workload-identity-disabled-test --namespace testing -- curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/?recursive=true | jq
{
  "aliases": [
    "default"
  ],
  "email": "503076227230-compute@developer.gserviceaccount.com",
  "scopes": [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/service.management.readonly",
    "https://www.googleapis.com/auth/servicecontrol",
    "https://www.googleapis.com/auth/trace.append"
  ]
}


# Alternatively you can use projected volume to obtain tokens instead of using the GKE_METADATA server
# See https://cloud.google.com/anthos/fleet-management/docs/use-workload-identity?hl=en#impersonate_a_service_account








root@fleet-workload-identity-test:/# gcloud --verbosity=debug auth application-default print-access-token
DEBUG: Running [gcloud.auth.application-default.print-access-token] with arguments: [--verbosity: "debug"]
DEBUG: Making request: POST https://sts.googleapis.com/v1/token
DEBUG: Starting new HTTPS connection (1): sts.googleapis.com:443
DEBUG: https://sts.googleapis.com:443 "POST /v1/token HTTP/1.1" 200 None
DEBUG: Making request: POST https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/test-sa@gregbray-vpc.iam.gserviceaccount.com:generateAccessToken
DEBUG: Starting new HTTPS connection (1): iamcredentials.googleapis.com:443
DEBUG: https://iamcredentials.googleapis.com:443 "POST /v1/projects/-/serviceAccounts/test-sa@gregbray-vpc.iam.gserviceaccount.com:generateAccessToken HTTP/1.1" 403 None
DEBUG: ('Unable to acquire impersonated credentials: No access token or invalid expiration in response.', '{\n  "error": {\n    "code": 403,\n    "message": "The caller does not have permission",\n    "status": "PERMISSION_DENIED"\n  }\n}\n')
Traceback (most recent call last):
  File "/usr/bin/../lib/google-cloud-sdk/lib/third_party/google/auth/impersonated_credentials.py", line 107, in _make_iam_token_request
    token = token_response["accessToken"]
KeyError: 'accessToken'






# Cluster WI testing using KSA mapped to GSA
root@workload-identity-test:/# curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" https://compute.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-a/instances
DEBUG: Running [gcloud.auth.application-default.print-access-token] with arguments: [--verbosity: "debug"]
DEBUG: Making request: GET http://169.254.169.254
DEBUG: Making request: GET http://metadata.google.internal/computeMetadata/v1/project/project-id
DEBUG: Making request: GET http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/?recursive=true
DEBUG: Starting new HTTP connection (1): metadata.google.internal:80
DEBUG: http://metadata.google.internal:80 "GET /computeMetadata/v1/instance/service-accounts/default/?recursive=true HTTP/1.1" 200 138
DEBUG: Making request: GET http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/test-sa@gregbray-vpc.iam.gserviceaccount.com/token?scopes=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform
DEBUG: http://metadata.google.internal:80 "GET /computeMetadata/v1/instance/service-accounts/test-sa@gregbray-vpc.iam.gserviceaccount.com/token?scopes=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform HTTP/1.1" 200 1083
INFO: Display format: "value(token)"
DEBUG: SDK update checks are disabled.
{
  "error": {
    "code": 403,
    "message": "Required 'compute.instances.list' permission for 'projects/gregbray-vpc'",
    "errors": [
      {
        "message": "Required 'compute.instances.list' permission for 'projects/gregbray-vpc'",
        "domain": "global",
        "reason": "forbidden"
      }
    ]
  }
}

# Cluster WI testing using KSA not mapped to GSA (but with role granting directly to WI instead of via GSA)
root@workload-identity-test:/# curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" https://compute.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-a/instances
DEBUG: Running [gcloud.auth.application-default.print-access-token] with arguments: [--verbosity: "debug"]
DEBUG: Making request: GET http://169.254.169.254
DEBUG: Making request: GET http://metadata.google.internal/computeMetadata/v1/project/project-id
DEBUG: Making request: GET http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/?recursive=true
DEBUG: Starting new HTTP connection (1): metadata.google.internal:80
DEBUG: http://metadata.google.internal:80 "GET /computeMetadata/v1/instance/service-accounts/default/?recursive=true HTTP/1.1" 200 118
DEBUG: Making request: GET http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/gregbray-vpc.svc.id.goog/token?scopes=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform
DEBUG: http://metadata.google.internal:80 "GET /computeMetadata/v1/instance/service-accounts/gregbray-vpc.svc.id.goog/token?scopes=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform HTTP/1.1" 200 1083
INFO: Display format: "value(token)"
DEBUG: SDK update checks are disabled.
{
  "error": {
    "code": 401,
    "message": "Request had invalid authentication credentials. Expected OAuth 2 access token, login cookie or other valid authentication credential. See https://developers.google.com/identity/sign-in/web/devconsole-project.",
    "errors": [
      {
        "message": "Invalid Credentials",
        "domain": "global",
        "reason": "authError",
        "location": "Authorization",
        "locationType": "header"
      }
    ],
    "status": "UNAUTHENTICATED"
  }
}


# Testing using Fleet identity and ADC mapped to GSA (but GSA doesn't have rights)
root@fleet-workload-identity-test:/# curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" https://compute.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-a/instances
DEBUG: Running [gcloud.auth.application-default.print-access-token] with arguments: [--verbosity: "debug"]
DEBUG: Making request: POST https://sts.googleapis.com/v1/token
DEBUG: Starting new HTTPS connection (1): sts.googleapis.com:443
DEBUG: https://sts.googleapis.com:443 "POST /v1/token HTTP/1.1" 200 None
DEBUG: Making request: POST https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/test-sa@gregbray-vpc.iam.gserviceaccount.com:generateAccessToken
DEBUG: Starting new HTTPS connection (1): iamcredentials.googleapis.com:443
DEBUG: https://iamcredentials.googleapis.com:443 "POST /v1/projects/-/serviceAccounts/test-sa@gregbray-vpc.iam.gserviceaccount.com:generateAccessToken HTTP/1.1" 200 None
DEBUG: Making request: GET https://cloudresourcemanager.googleapis.com/v1/projects/gregbray-fleet
DEBUG: Starting new HTTPS connection (1): cloudresourcemanager.googleapis.com:443
DEBUG: https://cloudresourcemanager.googleapis.com:443 "GET /v1/projects/gregbray-fleet HTTP/1.1" 403 None
DEBUG: Making request: POST https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/test-sa@gregbray-vpc.iam.gserviceaccount.com:generateAccessToken
DEBUG: Starting new HTTPS connection (1): iamcredentials.googleapis.com:443
DEBUG: https://iamcredentials.googleapis.com:443 "POST /v1/projects/-/serviceAccounts/test-sa@gregbray-vpc.iam.gserviceaccount.com:generateAccessToken HTTP/1.1" 200 None
INFO: Display format: "value(token)"
DEBUG: SDK update checks are disabled.
{
  "error": {
    "code": 403,
    "message": "Required 'compute.instances.list' permission for 'projects/gregbray-vpc'",
    "errors": [
      {
        "message": "Required 'compute.instances.list' permission for 'projects/gregbray-vpc'",
        "domain": "global",
        "reason": "forbidden"
      }
    ]
  }
}

# If the target GSA has correct permissions, you would see a "kind": "compute#instanceList" response instead of 403 error.
curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" https://container.googleapis.com/v1/projects/gregbray-vpc/locations/-/clusters?alt=json
https://compute.googleapis.com/compute/v1/projects/gregbray-vpc/zones/us-central1-a/instances

# And if the target api supports ubermint, you can grant permissions directly to the KSA
gcloud projects add-iam-policy-binding gregbray-vpc  \
 --member="serviceAccount:gregbray-fleet.svc.id.goog[testing/fleet-test-service-account]" \
 --role="roles/container.clusterViewer"

root@fleet-workload-identity-test:/# curl -sH "Authorization: Bearer $(gcloud --verbosity=debug auth application-default print-access-token)" https://container.googleapis.com/v1/projects/gregbray-vpc/locations/-/clusters?alt=json | head -n 25
DEBUG: Running [gcloud.auth.application-default.print-access-token] with arguments: [--verbosity: "debug"]
DEBUG: Making request: POST https://sts.googleapis.com/v1/token
DEBUG: Starting new HTTPS connection (1): sts.googleapis.com:443
DEBUG: https://sts.googleapis.com:443 "POST /v1/token HTTP/1.1" 200 None
DEBUG: Making request: GET https://cloudresourcemanager.googleapis.com/v1/projects/gregbray-fleet
DEBUG: Starting new HTTPS connection (1): cloudresourcemanager.googleapis.com:443
DEBUG: https://cloudresourcemanager.googleapis.com:443 "GET /v1/projects/gregbray-fleet HTTP/1.1" 403 None
DEBUG: Making request: POST https://sts.googleapis.com/v1/token
DEBUG: Starting new HTTPS connection (1): sts.googleapis.com:443
DEBUG: https://sts.googleapis.com:443 "POST /v1/token HTTP/1.1" 200 None
INFO: Display format: "value(token)"
DEBUG: SDK update checks are disabled.
{
  "clusters": [
    {... omitted ...

docs at https://cloud.google.com/anthos/fleet-management/docs/use-workload-identity
and internal https://g3doc.corp.google.com/company/gfw/support/cloud/playbooks/anthos/gke-hub/workload-identity.md?cl=head

IAM Policy
Confirm IAM policy is referring to the correct Workload Identity Pool. For example, if a cluster in project1 was registered to the Hub of project2, IAM policy must be written in terms of project2.svc.id.goog.
Confirm the Pod's kubernetes service account is bound to a GCP SA in IAM.
This was once a common requirement, as the target API must support UberMint to use WI without binding the KSA identity to a GSA identity. Many GCP APIs support UberMint now, so this requirement is becoming less common.
There is no easy way for a customer to tell if an API supports UberMint or not, so this may come up as a point of confusion if they try to use the "federated" token that just represents the Kubernetes SA (returned from securetoken.googleapis.com), instead of a token for a GCP SA, against an API that doesn't have UberMint support. If the customer claims that they are using the "federated" token, or that they are not mapping the KSA to a GCP SA, we can check if UberMint is enabled for the API they are trying to access by searching for the ESF YAML in codesearch: https://source.corp.google.com/search?q=uber_mint:%20mode:%20ENABLED

Does the fleet ID require using token projection? Trying iam.gke.io/gcp-service-account: "gregbray-fleet.svc.id.goog" failed:
root@fleet-workload-identity-test:/# curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/?recursive=true
Annotated service account must be in format of '[SA-NAME]@[PROJECT-ID].iam.gserviceaccount.com', '[SA_NAME]@appspot.gserviceaccount.com' or '[SA_NAME]@developer.gserviceaccount.com'

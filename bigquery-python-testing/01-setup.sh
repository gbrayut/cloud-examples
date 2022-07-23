# sample datasets https://cloud.google.com/bigquery/public-data hosted in US multiregion
# you must create your own dataset in same location if you want to copy the example datasets from the SQL Explorer

# local testing using default credentials https://cloud.google.com/sdk/gcloud/reference/auth/application-default/login
gcloud auth application-default login
# generates $HOME/.config/gcloud/application_default_credentials.json which is a known location the Client Libraries will use for ADC
# can also explicity export GOOGLE_APPLICATION_CREDENTIALS=/path/to/token (like $HOME/.config/gcloud/legacy_credentials/USERNAME/adc.json )

# change the default project that bigquery.Client() will use for datasets:
gcloud config set project myproject     # Doesn't work if using ADC
export GOOGLE_CLOUD_PROJECT=myproject   # Does work if using ADC

# to create bigquery jobs you need bigquery.jobUser permissions on the project or dataset
gcloud projects add-iam-policy-binding myproject \
 --member="serviceAccount:my-gsa@myproject.iam.gserviceaccount.com" \
 --role="roles/bigquery.jobUser"
# for GKE Workload Identity, use --member="serviceAccount:myproject.svc.id.goog[mynamespace/myksa]" 

# check GCE VM or GKE Pod location and default credentials via Metadata Server
curl -vsH "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/?recursive=true"

# Example output:
{
  "attributes": {
    "cluster-location": "us-central1",
    "cluster-name": "gke-iowa",
    "cluster-uid": "c94d71e8aa75442ebccae9c66a6d514374fcab49b9924250af8cb23ab47c5e3f"
  },
  "hostname": "gke-gke-iowa-test3-cb28af13-024g.us-central1-f.c.myproject.internal",
  "id": 3459945890685455400,
  "serviceAccounts": {
    "default": {
      "aliases": [
        "default"
      ],
      "email": "test-sa@myproject.iam.gserviceaccount.com",
      "scopes": [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    },
    "test-sa@myproject.iam.gserviceaccount.com": {
      "aliases": [
        "default"
      ],
      "email": "test-sa@myproject.iam.gserviceaccount.com",
      "scopes": [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  },
  "zone": "projects/123456227230/zones/us-central1-f"
}

# When using GKE Workload Identity without mapping KSA to a GSA you would instead
# see something like "email": "myproject.svc.id.goog" for the serviceAccounts section
# This is a temporary token (only valid for a few minutes) and may add additional latency
# since BigQuery has to exchange/extend it for a longer-lasting token

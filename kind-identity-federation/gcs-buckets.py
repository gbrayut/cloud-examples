import os
from google.cloud import storage

os.environ['GOOGLE_CLOUD_PROJECT'] = "gregbray-vpc"

# Instantiates a client
storage_client = storage.Client()

# List all the buckets available
[print(bucket) for bucket in storage_client.list_buckets()]

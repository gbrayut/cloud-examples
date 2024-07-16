import os
from google.cloud import storage

os.environ['GOOGLE_CLOUD_PROJECT'] = "gregbray-repo"

# Instantiates a client
storage_client = storage.Client()

# List all the buckets available
for bucket in storage_client.list_buckets():
    print(bucket)

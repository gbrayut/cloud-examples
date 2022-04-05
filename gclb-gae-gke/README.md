# Cross Project Google Cloud Load Balancer example

Note: this assumes the project in your [main.tf](./main.tf) file already exists and is already linked to a billing account and that the account used to run terraform has [Cloud Run permissions](https://cloud.google.com/run/docs/reference/iam/roles#additional-configuration).

## Overview

```bash
cd gclb-gae-gke
terraform init
terraform apply
```

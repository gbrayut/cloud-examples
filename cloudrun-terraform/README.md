# Cloud Run terraform example

Note: this assumes the project in your [main.tf](./main.tf) file already exists and is already linked to a billing account and that the account used to run terraform has [Cloud Run permissions](https://cloud.google.com/run/docs/reference/iam/roles#additional-configuration).

## Overview

Based on cloud_run_service [example usage](https://www.sethvargo.com/configuring-cloud-run-with-terraform/). See also https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#service_account_name.

```bash
cd cloudrun-terraform
terraform init
terraform apply
```

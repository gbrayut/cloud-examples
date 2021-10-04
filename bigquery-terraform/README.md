# BigQuery terraform example

Note: this assumes the project in your [main.tf](./main.tf) file already exists and is already linked to a billing account.

## Overview

Based on google_bigquery_table bar [example usage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_table#example-usage). See also https://cloud.google.com/blog/products/data-analytics/introducing-the-bigquery-terraform-module for a more elaborate example based on creating your own custom module.

```bash
cd bigquery-terraform
terraform init
terraform apply
```

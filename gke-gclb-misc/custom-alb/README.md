# Details on creating a manual/custom ALB

This roughly shows how to use Terraform ([main.tf](./main.tf)) to generate a URL Map with various basic path rules and more advanced match rules. The advanced routing rules are not available on Classic Application Load Balancers (type listed on [cloud console](https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers)).

You can also see the resulting [result-0-url-map.yaml](./result-0-url-map.yaml) and basic [result-1-path-matcher-net.yaml](./result-1-path-matcher-net.yaml) or advanced [result-2-path-matcher-com.yaml](./result-2-path-matcher-com.yaml) pathMatchers.

TODO: add more explicit steps for creating Backend Services attached to GKE Standalone NEG or using other types of backends (storage bucket, Internet NEG, serverless, etc).

## Terraform vs Cloud Console

The cloud console has a very basic UI and only lists a handful of examples on how to configure URL maps. I've found the [examples and documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) when using Terraform are much more comprehensive. It also provides a better overall development experience even if you later export/import/modify the raw URL map using [gcloud](https://docs.cloud.google.com/sdk/gcloud/reference/compute/url-maps) commands.

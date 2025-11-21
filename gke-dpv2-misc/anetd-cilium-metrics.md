# Scrape Cilium Metrics for GKE DPv2

GKE clusters usually now have [Managed Service for Prometheus](https://docs.cloud.google.com/stackdriver/docs/managed-prometheus/setup-managed) enabled by default, which you can use to monitor [Cilium eBPF](https://docs.cilium.io/en/stable/observability/metrics/#ebpf) metrics in GKE Dataplane V2 using [PodMonitoring](https://github.com/GoogleCloudPlatform/prometheus-engine/blob/main/doc/api.md#podmonitoring) resources. The [anetd-cilium-metrics.yaml](./anetd-cilium-metrics.yaml) example will start scraping the anetd metric endpoint for each node, which you can then query in [Metric Explorer](https://console.cloud.google.com/monitoring/metrics-explorer) using the PromQL example below.

If instead you are using OSS Prometheus, the anetd daemonset in kube-system namespace should already have the required `prometheus.io/scrape: "true"` annotation to enable scraping the **http://podname:9990/metrics** endpoint.

```shell
# Display bpf map usage (1.0 being 100% full) per cluster
# https://docs.cilium.io/en/stable/network/ebpf/maps/ for more details
max by ("map_name") (
  max_over_time({
    "__name__" = "cilium_bpf_map_pressure",
    "cluster" = "gke-iowa",
    "project_id" = "gregbray-vpc"
  }[${__interval}])
)
```

You can also create [Cloud Monitoring alerts](https://docs.cloud.google.com/monitoring/alerts) to try and prevent cilium_policy update error `no space left on device` when the bpf map runs out of space. See Isovalent [blog](https://isovalent.com/blog/post/isovalent-enterprise-cilium-dashboards/#bpf-map-pressure) and Cilium [docs](https://docs.cilium.io/en/stable/operations/troubleshooting/#policymap-pressure-and-overflow) for more details. Using [log-based metrics](https://cloud.google.com/logging/docs/alerting/monitoring-logs) to track and alert when those error messages occur is another useful strategy.

# API Server Control Plane Metrics

Another option is enabling [API Server monitoring](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/control-plane-metrics) for your GKE cluster and then alerting based on increases to the **apiserver_storage_objects** metric for Cilium resources. This won't show the total capacity or utilization, but if you have previously identified a limit on **ciliumendpoints.cilium.io** or **ciliumidentities.cilium.io** instances where your cluster starts having issues, you can track those objects by enabling API_SERVER monitoring. GKE Managed Service for Prometheus is still recommended but not required for SYSTEM and API_SERVER monitoring.

```shell
sum by ("resource","cluster")(
  avg_over_time({
    "__name__" = "apiserver_storage_objects",
    "resource" =~ "(cilium|networkpolicies|fqdnnetworkpolicies).*"
  }[${__interval}]))
```

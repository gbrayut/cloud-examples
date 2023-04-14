# Anthos Service Mesh Ingress Gateway Example

ASM [Ingress Gateways](https://cloud.google.com/service-mesh/docs/gateways) are not enabled by default but can be provisioned using either classic resources (Istio VirtualService and Gateway) or the new Kubernetes Gateway API. The Gateway API is still under active development and does not yet have all the same features as the Istio CRDs, but long term it is expected to be the preferred approach for configuring Load Balancers and Gateways.

The [From edge to mesh: Exposing service mesh applications through GKE Ingress](https://cloud.google.com/architecture/exposing-service-mesh-apps-through-gke-ingress) guide walks thru using GKE Ingress to route requests into an ASM cluster using an HTTPS GCLB. Here in this example we will instead use pass-through Network Load Balancer which allows the Envoy instance in the ingress gateway to manage TLS and other low-level connection settings.

## Provision Ingress Gateway using Istio Classic and Internal NLB

The [base-ingressgateway.yaml](./base-ingressgateway.yaml) manifest is copied from the [anthos-service-mesh-packages](https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/tree/main/samples/gateways) sample but excludes the service resource that creates the external Network Load Balancer. After applying the base you can then apply [svc-nlb-internal.yaml](./svc-nlb-internal.yaml) to create an internal NLB. The `istio-ingress` namespace should look like this:

```shell
$ kubectl get pod,svc,deploy,hpa -n istio-ingress 
NAME                                        READY   STATUS    RESTARTS   AGE
pod/istio-ingressgateway-5896f7f5c5-5d2fm   1/1     Running   0          11m
pod/istio-ingressgateway-5896f7f5c5-6pb5l   1/1     Running   0          11m
pod/istio-ingressgateway-5896f7f5c5-t924w   1/1     Running   0          11m

NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                                      AGE
service/istio-ingressgateway   LoadBalancer   10.64.117.137   10.31.232.40   15021:30200/TCP,80:30054/TCP,443:31557/TCP   53s

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/istio-ingressgateway   3/3     3            3           11m

NAME                                                       REFERENCE                         TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/istio-ingressgateway   Deployment/istio-ingressgateway   5%/80%    3         5         3          11m

NAME                                              MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/istio-ingressgateway   N/A             1                 1                     71m
```
_NOTE: Your istio-ingressgateway resources should be managed like any other Kubernetes application. The samples in the anthos-service-mesh-packages repo are meant for guidance and a quickstart and you should customize them according to your needs._

You can also use dedicated node pools (see nodeSelector/toleration section of base manifest) or deploy multiple Ingress Gateways to different namespaces and/or with different istio labels if desired as long as those namespaces have sidecar injection enabled.

## Istio Gateway and VirtualService

Once the istio-ingressgateway deployment is ready, you can then use Istio Gateway and VirtualService resources to route requests to your application via the Ingress Gateway. See [Gateway selector](https://cloud.google.com/service-mesh/docs/gateways#gateway_selectors) or [Istio docs](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/) for more details.

TODO: details on [istio-gw-virtualservice.yaml](./istio-gw-virtualservice.yaml)

## Alternative Load Balancer Options

Instead of using an Internal NLB, you can also use an external NLB by omitting the `networking.gke.io/load-balancer-type` annotation. The same istio-ingressgateway deployment can be targeted by multiple GCLB using multiple service resources, or you can have separate deployments if you want to isolate or scale them separately.

As the Kubernetes Gateway API expands, you will eventually be able to use those gateway and policy/config resources to control the load balancer and Envoy deployment. For example there is a preview of a [composite External GCLB and asm-ingressgateway](https://cloud.google.com/service-mesh/docs/managed/service-mesh-cloud-gateway) for managed ASM in Rapid channel, but it does currently come with certain limitations.

TODO: add [example](./svc-standalone-neg.yaml) for [standalone zonal neg](https://cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg) details for [tcp-proxy](https://cloud.google.com/load-balancing/docs/tcp/set-up-int-tcp-proxy-zonal) instead of pass-through NLB, also including Terraform managed HTTPS LB.

https://console.cloud.google.com/compute/networkendpointgroups/list

TODO: https://cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#attaching-int-https-lb
use those instructions then extract as terraform

also external https://cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg#attaching-ext-https-lb
Maybe also TCP Proxy LBs?  https://cloud.google.com/load-balancing/docs/negs/zonal-neg-concepts



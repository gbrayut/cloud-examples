# Details on creating a manual/custom NLB

TODO: fill in more details on options 1,2,3 from [ds-whereami](./ds-whereami.yaml) for combining multiple NEGs (possibly from different clusters in the same region) into one Passthru NLB

1) Use a deployment or daemonset with `hostNetwork: True` so the pod receives the packets from forwarding rule (no iptables NAT rule required). Daemonset makes it easy to prevent multiple pods on same node (causing port binding conflicts). But if you need to scale using an HPA then a dedicated nodepool that is sized to fit only one pod would also work.

2) If the port that clients use can be altered, then a manually specified nodeport on the Kubernetes Service with externalTrafficPolicy: Local would also work. But if clients are using port 443 and cannot be changed to a dedicated nodeport like 30443 then this option likely will not work.

3) The externalIPs value in Kubernetes Service is what controls creation of the NAT rules, and you can specify them for clusterip or nodeports as well (possibly also spec.loadBalancerIP with fake loadBalancerClass?). However due to potential for abuse you must create/update the cluster with `--enable-service-externalips` first. To prevent abuse you also would likely want to implement admission controller policies restricting use of `service.spec.externalIPs` to only the namespaces that need it.

4) Injecting custom NAT iptable rules to create the missing rule is technically possible using a privileged init container or DaemonSet. But that is well outside the scope of what GKE would officially support.

5) If you are comfortable creating Kubernetes Controllers, a custom GatewayClass and controller that supports this kind of multi-cluster L4 GCLB or manages the missing NAT rule would also be a good long term option.

## Packet capture via tshark

View packets routed to nodes (easiest to test using a single NEG on be-ilb)
TODO: switch to `kubectl debug node/gke-gke-iowa-default-pool-138fb5f3-x6jk ...`

```
gcloud compute ssh gke-gke-iowa-default-pool-138fb5f3-x6jk --project gregbray-gke-v1 --zone us-central1-a --tunnel-through-iap 
$ toolbox
# apt install tshark iproute2 less
# tshark -f "host 10.31.232.13 and src net 10.0.0.0/8 and dst net 10.0.0.0/8"
Running as user "root" and group "root". This could be dangerous.
Capturing on 'eth0'

    1 0.000000000 10.31.232.12 → 10.31.232.13 TCP 74 35028 → 80 [SYN] Seq=0 Win=65320 Len=0 MSS=1420 SACK_PERM=1 TSval=2460234034 TSecr=0 WS=128
    2 0.000063559 10.31.232.13 → 10.31.232.12 TCP 54 80 → 35028 [RST, ACK] Seq=1 Ack=1 Win=0 Len=0

    3 4.994187496 10.31.232.12 → 10.31.232.13 TCP 74 42900 → 18080 [SYN] Seq=0 Win=65320 Len=0 MSS=1420 SACK_PERM=1 TSval=2460239029 TSecr=0 WS=128
    4 4.994286194 10.31.232.13 → 10.31.232.12 TCP 54 18080 → 42900 [RST, ACK] Seq=1 Ack=1 Win=0 Len=0

    5 9.499230267 10.31.232.12 → 10.31.232.13 TCP 74 39756 → 30080 [SYN] Seq=0 Win=65320 Len=0 MSS=1420 SACK_PERM=1 TSval=2460243534 TSecr=0 WS=128
    6 9.499328345 10.31.232.13 → 10.31.232.12 ICMP 102 Destination unreachable (Port unreachable)

# above shows testing each port from VM in VPC but missing NAT rule.
# Last one is because target pod wasn't healthy
```

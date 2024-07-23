k apply -f base-whereami.yaml
k apply -f ./hostname-ingress.yaml
k get ingress -n test-gclb
k describe ingress -n test-gclb hostname-internal

INGRESS_EXT=$(kubectl get ingress -n test-gclb hostname-external -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
curl -vs -H "Host: example.com"     http://$INGRESS_EXT
curl -vs -H "Host: example.com:80"  http://$INGRESS_EXT
curl -vs -H "Host: example.com:99"  http://$INGRESS_EXT
# All the above request work, as the :port value in host header is ignored when using Classic ALB

# Test gce-internal using VM inside the VPC
INGRESS_INT=10.31.232.14
curl -vs -H "Host: example.com"     http://$INGRESS_INT
# the above works, but the remaining fail with response 404 (backend NotFound), service rules for the path non-existent
curl -vs -H "Host: example.com:80"  http://$INGRESS_INT
curl -vs -H "Host: example.com:99"  http://$INGRESS_INT
# Envoy based regional internal ALB by default requires explicit matching if client includes :port in the host header
# But the ingress resource won't allow using :port at all. See https://github.com/kubernetes-client/c/blob/master/kubernetes/docs/v1_ingress_rule.md
# The Ingress "hostname-internal" is invalid: spec.rules[0].host: Invalid value: "example.com:80": a lowercase RFC 1123 subdomain must consist of lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character (e.g. 'example.com', regex used for validation is '[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*')

# Workaround... omit host section and use dedicated ILB per hostname. Could also use something in-cluster to do hostname based routing

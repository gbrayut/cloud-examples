# Based on https://istio.io/latest/docs/tasks/traffic-management/ingress/secure-ingress/
mkdir example_certs

# Self-Signed Wildcard Certificate Config
cat << EOF > ./example_certs/star-example.conf
[req]
default_bits              = 2048
req_extensions            = extension_requirements
distinguished_name        = dn_requirements
prompt                    = no
[extension_requirements]
basicConstraints          = CA:FALSE
keyUsage                  = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName            = @sans_list
[dn_requirements]
0.organizationName        = example
commonName                = *.example.com
[sans_list]
DNS.1                     = *.example.com
EOF

# New private key and wildcard Certificate Signing Request
openssl genrsa -out example_certs/star.pem 2048
openssl req -new -config example_certs/star-example.conf \
  -key example_certs/star.pem -out example_certs/star.csr

# Generate public x509 certificate from CSR and private key
openssl x509 -req -signkey example_certs/star.pem -in example_certs/star.csr \
  -out example_certs/star.crt -extfile example_certs/star-example.conf \
  -extensions extension_requirements -days 365

# Upload for use in GCLB
gcloud compute ssl-certificates create star-example-com \
  --certificate=example_certs/star.crt --private-key=example_certs/star.pem \
  --global --project my-gcp-project

# Upload to GKE for use in istio-ingressgateway (Must be same namespace as gateway)
kubectl create -n istio-ingress secret tls shared-istio-gw-wildcard-cert \
  --key=example_certs/star.pem --cert=example_certs/star.crt

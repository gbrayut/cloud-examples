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


PROJECT_ID=gregbray-testing

# New private key and wildcard Certificate Signing Request
openssl genrsa -out example_certs/star-example.pem 2048
openssl req -new -config example_certs/star-example.conf \
  -key example_certs/star-example.pem -out example_certs/star-example.csr

# Generate public x509 certificate from CSR and private key
openssl x509 -req -signkey example_certs/star-example.pem -in example_certs/star-example.csr \
  -out example_certs/star-example.crt -extfile example_certs/star-example.conf \
  -extensions extension_requirements -days 3650

# Certificate Manager global self-managed certificate for use in global cert maps
gcloud services enable certificatemanager.googleapis.com --project $PROJECT_ID
gcloud certificate-manager certificates create wildcard-example --project $PROJECT_ID \
    --certificate-file="./example_certs/star-example.crt" \
    --private-key-file="./example_certs/star-example.pem"

# Create global certificate map with one default entry
gcloud certificate-manager maps create gke-gateway-map --location global --project $PROJECT_ID
gcloud certificate-manager maps entries create default-wildcard --project $PROJECT_ID \
  --map gke-gateway-map --certificates wildcard-example --set-primary

# Also create a Regional Certificate for use in Regional ALB / Inference Gateway (no cert map)
gcloud certificate-manager certificates create uc1-wildcard --project $PROJECT_ID \
    --certificate-file="./example_certs/star-example.crt" \
    --private-key-file="./example_certs/star-example.pem" \
    --location="us-central1"

# Or upload to GKE cluster for use in istio-ingressgateway (Must be same namespace as gateway deployment)
kubectl create -n istio-ingress secret tls shared-istio-gw-wildcard-cert \
  --key=example_certs/star-example.pem --cert=example_certs/star-example.crt

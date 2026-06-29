#

kubectl apply -f https://github.com/gbrayut/cloud-examples/raw/refs/heads/main/gke-gclb-misc/base-whereami.yaml

kubectl create configmap client-issuing-ca -n test-gclb \
  --from-file=ca.crt=/mnt/shared/code/saved/ghostunnel/certs/issuer.mtls.example.com.crt

k apply -f /home/gregbray/code/github/cloud-examples-2/gke-gclb-misc/frontend-mtls/global-alb-frontend-mtls.yaml

```shell
kurl -sk --cert client-123.mtls.example.com.crt --key client-123.mtls.example.com.key --resolve example.com:443:$ALB_IP https://example.com | jq '.headers' | tee /tmp/headers.json
{
  "Accept": "*/*",
  "Host": "example.com",
  "User-Agent": "curl/8.20.0",
  "Via": "1.1 google",
  "X-Cloud-Trace-Context": "682cbc3d80841b97ff71894d323b7313/1199248357223208368",
  "X-Forwarded-For": "98.32.71.177,136.68.173.39",
  "X-Forwarded-Proto": "https",
  "X-Mtls-Cert-Leaf": "",
  "X-Mtls-Details": "present:true verified:true error:",
  "X-Mtls-Fingerprint": "b3sFlNlCkzlL0VvbiwqjTTFisd5bssdayLSSwx18AuI",
  "X-Mtls-Sans-Dns": "Y2xpZW50LTEyMy5tdGxzLmV4YW1wbGUuY29t",
  "X-Mtls-Serial-Number": "00:9a:24:3d:49:a2:2c:b6:64:e0:b4:88:aa:27:6c:b1:8b",
  "X-Mtls-Subject": "MCYxJDAiBgNVBAMTG2NsaWVudC0xMjMubXRscy5leGFtcGxlLmNvbQ=="
}

openssl x509 -in client-123.mtls.example.com.crt -noout -fingerprint -sha256
sha256 Fingerprint=6F:7B:05:94:D9:42:93:39:4B:D1:5B:DB:8B:0A:A3:4D:31:62:B1:DE:5B:B2:C7:5A:C8:B4:92:C3:1D:7C:02:E2

jq -r '."X-Mtls-Fingerprint"' /tmp/headers.json | basenc --base64url --decode | od -An -v -tx1
 6f 7b 05 94 d9 42 93 39 4b d1 5b db 8b 0a a3 4d
 31 62 b1 de 5b b2 c7 5a c8 b4 92 c3 1d 7c 02 e2

jq -r '."X-Mtls-Sans-Dns"|@base64d' /tmp/headers.json
client-123.mtls.example.com

jq -r '."X-Mtls-Subject"' /tmp/headers.json | basenc --base64url --decode | openssl asn1parse -inform DER
    0:d=0  hl=2 l=  38 cons: SEQUENCE          
    2:d=1  hl=2 l=  36 cons: SET               
    4:d=2  hl=2 l=  34 cons: SEQUENCE          
    6:d=3  hl=2 l=   3 prim: OBJECT            :commonName
   11:d=3  hl=2 l=  27 prim: PRINTABLESTRING   :client-123.mtls.example.com
```

# Cloud Run terraform example

Note: this assumes the project in your [app.tf](./app.tf) file already exists and is already linked to a billing account and that the account used to run terraform has [Cloud Run permissions](https://cloud.google.com/run/docs/reference/iam/roles#additional-configuration).

## Overview

Based on cloud_run_service [secret examples](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service#example-usage---cloud-run-service-secret-volumes). This uses a modified version of the echoserver container to print out the Environment Variables and mounted Volumes for accessing secrets. Alternatively there is also [cloudrun-hello-go](./cloudrun-hello-go) that shows how to access secrets from Golang.

See also https://cloud.google.com/secret-manager/docs/best-practices

```bash
cd cloudrun-secrets
terraform init
terraform apply
# May have to apply multiple times if the APIs havent been enabled for your project yet.

# Results when loading Cloud Run website
Hostname: N/A

Pod Information:
	-no pod information available-

Server values:
	server_version=nginx: 1.12.2 - lua: 10010

Request Information:
	client_address=169.254.8.129
	method=GET
	real path=/
	query=
	request_version=1.1
	request_scheme=http
	request_uri=http://my-service-asdfasdf-uc.a.run.app:8080/

Request Headers:
	accept=text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9
	accept-encoding=gzip, deflate, br
	accept-language=en-US,en;q=0.9
	cache-control=max-age=0
	forwarded=for=&quot;1234:567:8901:96f1:5ac3:9ab7:5490:43a7&quot;;proto=https
	host=my-service-asdfasdf-uc.a.run.app
	sec-ch-ua=&quot;Google Chrome&quot;;v=&quot;95&quot;, &quot;Chromium&quot;;v=&quot;95&quot;, &quot;;Not A Brand&quot;;v=&quot;99&quot;
	sec-ch-ua-mobile=?0
	sec-ch-ua-platform=&quot;Linux&quot;
	sec-fetch-dest=document
	sec-fetch-mode=navigate
	sec-fetch-site=none
	sec-fetch-user=?1
	traceparent=00-0e16572461c09e34d675b3030148f82c-6dd682beb16e301c-01
	upgrade-insecure-requests=1
	user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36
	x-client-data=CgSL6ZsV
	x-cloud-trace-context=0e16572461c09e34d675b3030148f82c/7914657150682411036;o=1
	x-forwarded-for=1234:567:890196f1:5ac3:9ab7:5490:43a7
	x-forwarded-proto=https

Request Body:
	-no body in request-

env and Secrets:
K_REVISION=my-service-7kzdm
SHLVL=1
PORT=8080
HOME=/home
K_CONFIGURATION=my-service
NGINX_VERSION=1.15.2
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
K_SERVICE=my-service
PWD=/
SECRET_ENV_VAR_FAKE=secret-data
-r--r--r--    1 root     root            11 Nov 16 03:22 /secrets/not-a-real-secret
secret-data
```

The above is just a sample output (statically embeded in the config file at [startup](./cloudrun-secrets/app.tf#L58)) which also shows the three ways of accessing secrets:

> Mount each secret as a volume, which makes the secret available to the container as files. Reading a volume always fetches the secret value from Secret Manager, so it can be used with the latest version. This method also works well with secret rotation.
>
> Pass a secret using environment variables. Environment variables are resolved at instance startup time, so if you use this method, Google recommends that you pin the secret to a particular version rather than using latest.
For more information, refer to the Secret Manager best practices document.

And the third being direct access via [Cloud APIs](https://cloud.google.com/secret-manager/docs/reference/libraries). This approach can be a bit more work but give full contron and is slightly more secure since it [prevents](https://cloud.google.com/secret-manager/docs/best-practices#coding_practices) some attack vectors, but for the vast majority of case any of the above should be fine

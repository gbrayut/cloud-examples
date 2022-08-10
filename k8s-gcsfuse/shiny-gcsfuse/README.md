# GCS Fuse Shiny Server Example

WIP

```shell
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build and push images
docker build --tag us-central1-docker.pkg.dev/gregbray-repo/test/shiny-gcsfuse:latest shiny-gcsfuse
docker push us-central1-docker.pkg.dev/gregbray-repo/test/shiny-gcsfuse:latest

gcloud artifacts docker images list us-central1-docker.pkg.dev/gregbray-repo/test --include-tags

# Test locally using port forwarding
kubectl port-forward -n testfuse service/shiny-server 8000:80
```

## Other Links

* https://shinyproxy.io/

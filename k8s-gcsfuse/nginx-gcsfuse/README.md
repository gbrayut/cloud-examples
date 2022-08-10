# GCS Fuse Nginx Example

WIP 

```shell
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build and push images
docker build --tag us-central1-docker.pkg.dev/gregbray-repo/test/nginx-gcsfuse:latest nginx-gcsfuse
docker push us-central1-docker.pkg.dev/gregbray-repo/test/nginx-gcsfuse:latest

gcloud artifacts docker images list us-central1-docker.pkg.dev/gregbray-repo/test --include-tags


# These errors may mean gcsfuse may need -o allow_other
root@web-server-57c8c7476-9l7v2:/# cat /var/log/nginx/error.log
2022/08/10 02:37:09 [crit] 7#7: *2 stat() "/var/www/html/" failed (13: Permission denied), client: 10.31.236.16, server: _, request: "GET / HTTP/1.1", host: "10.120.4.28"

root@web-server-57c8c7476-9l7v2:/# sudo -u www-data stat /var/www/html
stat: cannot stat '/var/www/html': Permission denied
```

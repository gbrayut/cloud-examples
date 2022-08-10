# GCS Fuse Testing

WIP ... see [nginx-gcsfuse](./nginx-gcsfuse) and [shiny-gcsfuse](./shiny-gcsfuse) directories

```shell
# Get/Change IAM permissions on GCS Bucket
gsutil iam get gs://gregbray-repo-gcs
gsutil iam ch serviceAccount:gregbray-vpc.svc.id.goog[testfuse/default]:objectViewer gs://gregbray-repo-gcs
```

## Other Links

* https://cloud.google.com/filestore/docs/multishares
* https://cloud.google.com/run/docs/tutorials/network-filesystems-fuse
* https://github.com/ofek/csi-gcs/
* https://pliutau.com/mount-gcs-bucket-k8s/

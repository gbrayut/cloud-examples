# This often works https://cloud.google.com/sdk/gcloud/reference/components
gcloud components install kubectl

# Debian VMs:
sudo apt-get update
sudo apt-get install kubectl

# Setup contexts for accessing clusters
gcloud container clusters get-credentials test-cluster --zone us-central1-a

# Switch between corp/demo accounts
gcloud config configurations list
gcloud config configurations activate default

# Switch between cluster contexts (may also need to switch )
kubectl config get-contexts
kubectl config set-context gke_demo2021-310119_us-central1-a_test-cluster

# Run a temporary test pod (optional -n mynamespace)
kubectl run test-pod --rm -it --image=marketplace.gcr.io/google/ubuntu1804 -- /bin/bash

# https://cloud.google.com/container-registry/docs/managed-base-images

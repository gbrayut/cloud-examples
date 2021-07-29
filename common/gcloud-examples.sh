# gcloud configs
gcloud config configurations list
gcloud config configurations activate altostrat
gcloud init # Create new config... saved in ~/.config/gcloud/configurations

# gcloud SSH from laptop 
# https://cloud.google.com/sdk/gcloud/reference/compute/config-ssh
# https://cloud.google.com/sdk/gcloud/reference/compute/ssh
ssh-add /home/$USER/.ssh/google_compute_engine # Add ssh key to agent for single password entry while session is active
gcloud compute ssh test-registry
gcloud compute ssh test-registry --tunnel-through-iap -- -L 8443:localhost:443 # Port forwarding local 8443 -> VM 443 (for a background session use suffix -N &)

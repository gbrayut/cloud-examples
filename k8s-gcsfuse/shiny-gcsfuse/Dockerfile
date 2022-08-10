# See https://github.com/GoogleCloudPlatform/gcsfuse/blob/master/docs/installing.md

FROM rocker/shiny

RUN apt-get update
RUN apt-get install -y gnupg lsb-release wget

RUN lsb_release -c -s > /tmp/lsb_release
RUN GCSFUSE_REPO=$(cat /tmp/lsb_release); echo "deb http://packages.cloud.google.com/apt gcsfuse-$GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list
RUN wget -O - https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

RUN apt-get update
RUN apt-get install -y gcsfuse

# Make mountpoint for gcsfuse
RUN mkdir -p /srv/shiny-server/gcs

# see https://code.markedmondson.me/googleCloudRunner/articles/usecase-shiny-kubernetes.html
# install R package dependencies
RUN apt-get install -y \
    libssl-dev \
    ## clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/ \
    && rm -rf /tmp/downloaded_packages/ /tmp/*.rds

## Install packages from CRAN
RUN install2.r --error \
    -r 'http://cran.rstudio.com' \
        remotes \
        shinyjs \
    ## install Github packages
    && installGithub.r MarkEdmondson1234/googleCloudRunner \
    ## clean up
    && rm -rf /tmp/downloaded_packages/ /tmp/*.rds

VOLUME ["/srv/shiny-server"]
EXPOSE 3838

RUN mkdir scripts
COPY entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh
ENTRYPOINT ["bin/bash", "/scripts/entrypoint.sh"]
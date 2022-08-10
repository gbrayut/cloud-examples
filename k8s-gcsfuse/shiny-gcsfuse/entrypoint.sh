#!/bin/bash

#gcsfuse my-bucket /usr/bin/shiny-server/gcs

# Use exec to make sure new process handles SIGTERM and other signals
#/bin/bash -c 'exec sudo -u shiny /usr/bin/shiny-server'

tail -f /dev/null # Sleep forever for testing container (will override command in deployment yaml)
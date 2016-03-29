#!/usr/bin/env bash

echo Internal Build Running
echo GIT_REPO_OWNER=${GIT_REPO_OWNER}
echo GIT_REPO_NAME=${GIT_REPO_NAME}
sleep 1
echo "master_build: true" >> $METRICS_DATA_FILE
echo Master Build Complete
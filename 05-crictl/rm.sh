#!/bin/sh

export DOWNLOAD_DIR="/usr/local/bin"
rm -rf $DOWNLOAD_DIR
rm -rf /etc/crictl.yaml

hash -r

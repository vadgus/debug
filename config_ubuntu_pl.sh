#!/bin/bash

# fix apt sources to use https and .pl mirror
sources_file="/etc/apt/sources.list"
if [[ -f "$sources_file" ]]; then
  sed -i -E 's|http://|https://|g' "$sources_file"
  sed -i -E 's|[a-z]{2}\\.archive\\.ubuntu\\.com|pl.archive.ubuntu.com|g' "$sources_file"
  sed -i -E 's|[a-z]{2}\\.security\\.ubuntu\\.com|security.ubuntu.com|g' "$sources_file"
fi
apt-get update
apt-get upgrade -y || true

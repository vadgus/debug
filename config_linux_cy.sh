#!/bin/bash

timedatectl set-timezone Asia/Nicosia
source /etc/default/locale

# fix apt sources to use https and .cy mirror
sources_file="/etc/apt/sources.list.d/ubuntu.sources"
sources_list="/etc/apt/sources.list"

if [ -f "$sources_file" ]; then
    sed -i 's|http://|https://|g' "$sources_file"
    sed -i -E 's|[a-z0-9]+\.archive\.ubuntu\.com|cy.archive.ubuntu.com|g' "$sources_file"
    sed -i -E 's|[a-z0-9]+\.security\.ubuntu\.com|security.ubuntu.com|g' "$sources_file"
elif [ -f "$sources_list" ]; then
    sed -i 's|http://|https://|g' "$sources_list"
    sed -i -E 's|[a-z0-9]+\.archive\.ubuntu\.com|cy.archive.ubuntu.com|g' "$sources_list"
    sed -i -E 's|[a-z0-9]+\.security\.ubuntu\.com|security.ubuntu.com|g' "$sources_list"
fi

apt-get update
apt-get upgrade -y || true

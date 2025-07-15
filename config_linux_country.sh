#!/bin/bash

# Set timezone and mirror based on argument
# Usage: ./config_linux_country.sh cy | pl | ua | kz | za
# Usage remote: 'curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/config_linux_country.sh | sudo bash -s cy'

case "$1" in
    cy)
        timezone="Asia/Nicosia"
        mirror="cy.archive.ubuntu.com"
        ;;
    pl)
        timezone="Europe/Warsaw"
        mirror="pl.archive.ubuntu.com"
        ;;
    ua)
        timezone="Europe/Kyiv"
        mirror="ua.archive.ubuntu.com"
        ;;
    kz)
        timezone="Asia/Almaty"
        mirror="kz.archive.ubuntu.com"
        ;;
    za)
        timezone="Africa/Johannesburg"
        mirror="za.archive.ubuntu.com"
        ;;
    *)
        echo "Usage: $0 {cy|za|kz|pl|ua}"
        exit 1
        ;;
esac

timedatectl set-timezone "$timezone"
source /etc/default/locale

sources_file="/etc/apt/sources.list.d/ubuntu.sources"
sources_list="/etc/apt/sources.list"

if [ -f "$sources_file" ]; then
    sed -i 's|http://|https://|g' "$sources_file"
    sed -i -E "s|[a-z0-9]+\.archive\.ubuntu\.com|$mirror|g" "$sources_file"
    sed -i -E 's|[a-z0-9]+\.security\.ubuntu\.com|security.ubuntu.com|g' "$sources_file"
elif [ -f "$sources_list" ]; then
    sed -i 's|http://|https://|g' "$sources_list"
    sed -i -E "s|[a-z0-9]+\.archive\.ubuntu\.com|$mirror|g" "$sources_list"
    sed -i -E 's|[a-z0-9]+\.security\.ubuntu\.com|security.ubuntu.com|g' "$sources_list"
fi

apt-get update
apt-get upgrade -y || true

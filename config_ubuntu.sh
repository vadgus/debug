#!/bin/bash
set -e

# get real username and paths
real_user=$(logname)
user_home="/home/$real_user"
bashrc_file="$user_home/.bashrc"

# install basic packages
apt-get update
apt-get install -y openssh-server curl git tmux

# allow passwordless sudo
echo "$real_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$real_user
chmod 0440 /etc/sudoers.d/$real_user

# set timezone and locale
update-locale LANG=en_US.UTF-8
update-locale LC_TIME=en_ZW.UTF-8
timedatectl set-timezone Europe/Warsaw
source /etc/default/locale

# install venv for system python version
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
apt-get install -y "python$PYTHON_VERSION-venv"

# fix apt sources from any country to .pl and force https
sources_file=""
if [ -f /etc/apt/sources.list ]; then
    sources_file="/etc/apt/sources.list"
elif [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sources_file="/etc/apt/sources.list.d/ubuntu.sources"
fi

if [[ -n "$sources_file" ]]; then
    sed -i 's|http://|https://|g' "$sources_file"
    sed -i 's|[a-z]\{2,\}\.archive\.ubuntu\.com|pl.archive.ubuntu.com|g' "$sources_file"
    sed -i 's|[a-z]\{2,\}\.security\.ubuntu\.com|security.ubuntu.com|g' "$sources_file"
fi

# update and upgrade system
apt-get update
apt-get upgrade -y || true
apt-get autoremove -y || true

# disable apt motd noise
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f \( -name '*header*' -o -name '*reboot-required*' \) -exec chmod +x {} \;
pro config set apt_news=false 2>/dev/null || true

# enable lightdm autologin
echo -e "[Seat:*]\nautologin-user=$real_user\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf
chmod 644 /etc/lightdm/lightdm.conf
systemctl daemon-reexec || true
systemctl restart lightdm || true

# disable unwanted background services
systemctl disable unattended-upgrades || true
systemctl disable apport.service || true
systemctl disable bluetooth.service || true

# disable XFCE screensaver if present
sudo -u "$real_user" dbus-launch xfconf-query -c xfce4-screensaver -p /saver --create -t string -s blank-only || true

# add useful aliases
if grep -q "^alias ll=" "$bashrc_file"; then
    sed -i "s|^alias ll=.*|alias ll='ls -lah'|" "$bashrc_file"
else
    echo "alias ll='ls -lah'" >> "$bashrc_file"
fi

# upgrade alias
echo "alias upgrade='sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y'" >> "$bashrc_file"

# install docker if missing
if ! command -v docker &>/dev/null; then
    snap install docker
    groupadd docker || true
    usermod -aG docker "$real_user"
    echo 'newgrp docker' >> "$bashrc_file"
fi

# detect desktop environment
desktop_env=$(echo "${XDG_CURRENT_DESKTOP:-$(sudo -u "$real_user" printenv XDG_CURRENT_DESKTOP)}" | tr '[:upper:]' '[:lower:]')

# apply GUI settings
if [[ "$desktop_env" == *"xfce"* ]] || pgrep -u "$real_user" xfce4-session >/dev/null 2>&1; then
    apt-get install -y greybird-gtk-theme

    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" --create -t string || true
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" --create -t string || true

    background_path="/usr/share/backgrounds/xfce/xfce-blue.jpg"
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "$background_path" --create -t string || true
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfdesktop --reload || true

    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xfce4-notifyd -p /do-not-disturb -s true --create -t bool || true

elif [[ "$desktop_env" == *"gnome"* ]] || pgrep -u "$real_user" gnome-session >/dev/null 2>&1; then
    apt-get install -y gnome-tweaks

    sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Yaru-dark' || true

    if gsettings list-schemas | grep -q "org.gnome.settings-daemon.plugins.power"; then
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power power-saver-profile-on-low-battery false
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    fi

    if gsettings list-schemas | grep -q "org.gnome.desktop.notifications"; then
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.notifications show-banners false
    fi
fi

# install QModBus
bash -c "$(curl -fsSL https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/install_qmodbus.sh)" || true

# finish
echo "[✓] System configuration complete. Reboot required."

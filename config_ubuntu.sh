#!/bin/bash
set -e

real_user=$(logname)
user_home="/home/$real_user"
bashrc_file="$user_home/.bashrc"

# install basic packages
apt-get update
apt-get install -y openssh-server curl git tmux

# allow passwordless sudo
echo "$real_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$real_user
chmod 0440 /etc/sudoers.d/$real_user

# set locale and timezone
update-locale LANG=en_US.UTF-8
update-locale LC_TIME=en_ZW.UTF-8
timedatectl set-timezone Europe/Warsaw
source /etc/default/locale

# install venv for system python
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
apt-get install -y "python$PYTHON_VERSION-venv"

# fix apt sources
# In Ubuntu 22.04 and earlier, sources are in /etc/apt/sources.list
# In Ubuntu 23.10 and later, main config is in /etc/apt/sources.list.d/ubuntu.sources
sources_file="/etc/apt/sources.list"
if [ ! -s "$sources_file" ]; then
    sources_file=$(find /etc/apt/sources.list.d/ -name '*.sources' | head -n1)
fi

# replace all XX.archive.ubuntu.com and http → https
if [[ -n "$sources_file" ]]; then
    sed -i -E 's|http://|https://|g' "$sources_file"
    sed -i -E 's|[a-z]{2}\.archive\.ubuntu\.com|pl.archive.ubuntu.com|g' "$sources_file"
    sed -i -E 's|[a-z]{2}\.security\.ubuntu\.com|security.ubuntu.com|g' "$sources_file"
    apt-get update
    apt-get upgrade -y || true
fi

# disable apt motd messages
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f \( -name '*header*' -o -name '*reboot-required*' \) -exec chmod +x {} \;
pro config set apt_news=false 2>/dev/null || true

# enable autologin in lightdm
echo -e "[Seat:*]\nautologin-user=$real_user\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf
chmod 644 /etc/lightdm/lightdm.conf
systemctl restart lightdm || true

# disable unattended-upgrades
systemctl disable unattended-upgrades || true

# disable apport (error reports)
systemctl disable apport.service || true

# disable bluetooth
systemctl disable bluetooth.service || true

# disable xfce screensaver if available
sudo -u "$real_user" dbus-launch xfconf-query -c xfce4-screensaver -p /saver --create -t string -s blank-only || true

# add useful aliases
if grep -q "^alias ll=" "$bashrc_file"; then
    sed -i "s|^alias ll=.*|alias ll='ls -lah'|" "$bashrc_file"
else
    echo "alias ll='ls -lah'" >> "$bashrc_file"
fi

echo "alias upgrade='sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y && sudo reboot'" >> "$bashrc_file"

# install docker if missing
if ! command -v docker &>/dev/null; then
    snap install docker
    groupadd docker || true
    usermod -aG docker "$real_user"
    echo 'newgrp docker' >> "$bashrc_file"
fi

# determine desktop environment
desktop_env=$(echo "${XDG_CURRENT_DESKTOP:-$(sudo -u $real_user printenv XDG_CURRENT_DESKTOP)}" | tr '[:upper:]' '[:lower:]')

# theme and background for XFCE
if [[ "$desktop_env" == *"xfce"* ]] || pgrep -u "$real_user" xfce4-session >/dev/null 2>&1; then
    apt-get install -y greybird-gtk-theme

    # set dark theme
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" --create -t string || true
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" --create -t string || true

    # set background
    background_path="/usr/share/backgrounds/xfce/xfce-blue.jpg"
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "$background_path" --create -t string || true
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfdesktop --reload || true

    # enable Do Not Disturb
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xfce4-notifyd -p /do-not-disturb -s true --create -t bool || true
fi

# theme and power settings for GNOME
if [[ "$desktop_env" == *"gnome"* ]] || pgrep -u "$real_user" gnome-session >/dev/null 2>&1; then
    apt-get install -y gnome-tweaks

    # set dark theme
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
    sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Yaru-dark' || true

    # power mode: performance
    if gsettings list-schemas | grep -q "org.gnome.settings-daemon.plugins.power"; then
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power power-saver-profile-on-low-battery false
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    fi

    # do not disturb (GNOME)
    if gsettings list-schemas | grep -q "org.gnome.desktop.notifications"; then
        sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.notifications show-banners false
    fi
fi

# install qmodbus from github
bash -c "$(curl -fsSL https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/install_qmodbus.sh)" || true

echo "[✓] System configuration complete. Reboot required."

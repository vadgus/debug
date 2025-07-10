#!/bin/bash
set -e

# get real username
real_user=$(logname)
user_home="/home/$real_user"
bashrc_file="$user_home/.bashrc"

# install base packages
apt-get update
apt-get upgrade -y || true
apt-get install -y openssh-server curl git tmux

# allow passwordless sudo
echo "$real_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$real_user
chmod 0440 /etc/sudoers.d/$real_user

# set locale and timezone
update-locale LANG=en_US.UTF-8
update-locale LC_TIME=en_ZW.UTF-8
source /etc/default/locale

# install venv for system python
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
apt-get install -y "python$PYTHON_VERSION-venv"
apt-get install -y "python$PYTHON_VERSION-tk"

# disable apt motd messages
find /etc/update-motd.d/ -type f -exec chmod -x {} \;
find /etc/update-motd.d/ -type f \( -name '*header*' -o -name '*reboot-required*' \) -exec chmod +x {} \;
pro config set apt_news=false 2>/dev/null || true

# enable autologin in lightdm
echo -e "[Seat:*]\nautologin-user=$real_user\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf
chmod 644 /etc/lightdm/lightdm.conf
systemctl restart lightdm || true

# disable services: upgrade notifier, error reporting, bluetooth
systemctl disable unattended-upgrades || true
systemctl disable apport || true
systemctl disable bluetooth || true

# add useful aliases
if grep -q "^alias ll=" "$bashrc_file"; then
  sed -i "s|^alias ll=.*|alias ll='ls -lah'|" "$bashrc_file"
else
  echo "alias ll='ls -lah'" >> "$bashrc_file"
fi

# remove old upgrade alias and add new one
sed -i '/alias upgrade=/d' "$bashrc_file"
echo "alias upgrade='sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y && sudo apt-get autoclean -y'" >> "$bashrc_file"

# install docker if missing
if ! command -v docker &>/dev/null; then
  snap install docker
  groupadd docker || true
  usermod -aG docker $real_user
  echo 'newgrp docker' >> "$bashrc_file"
fi

# determine desktop environment
desktop_env=$(echo "${XDG_CURRENT_DESKTOP:-$(sudo -u $real_user printenv XDG_CURRENT_DESKTOP)}" | tr '[:upper:]' '[:lower:]')

if [[ "$desktop_env" == *"xfce"* ]] || pgrep -u $real_user xfce4-session >/dev/null 2>&1; then
  apt-get install -y greybird-gtk-theme

  # apply theme
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/ThemeName -s "Greybird-dark" --create -t string
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary-xfce-dark" --create -t string

  # disable screensaver
  sudo -u "$real_user" dbus-launch xfconf-query -c xfce4-screensaver -p /saver --create -t string -s blank-only || true

  # disable notifications
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s true || true

  # set wallpaper
  sudo -u "$real_user" xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "/usr/share/backgrounds/xfce/xfce-blue.jpg" || true

  # setup autostart to reload desktop (needed for wallpaper sometimes)
  autostart_dir="$user_home/.config/autostart"
  mkdir -p "$autostart_dir"
  cat <<EOF > "$autostart_dir/xfdesktop-reload.desktop"
[Desktop Entry]
Type=Application
Name=XFDesktop Reload
Exec=sh -c 'sleep 3 && pkill -HUP xfdesktop'
X-GNOME-Autostart-enabled=true
EOF
  chown "$real_user:$real_user" "$autostart_dir/xfdesktop-reload.desktop"
fi

if [[ "$desktop_env" == *"gnome"* ]] || pgrep -u $real_user gnome-session >/dev/null 2>&1; then
  apt-get install -y gnome-tweaks

  # apply dark theme
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Yaru-dark'

  # disable notifications
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.desktop.notifications show-banners false || true

  # try disable power save
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' || true
  sudo -u "$real_user" env DISPLAY=:0 dbus-launch gsettings set org.gnome.settings-daemon.plugins.power power-saver-profile-on-low-battery false || true
fi

# install qmodbus from github
bash -c "$(curl -fsSL https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/install_qmodbus.sh)" || true

echo "[✓] System configuration complete."

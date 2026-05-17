#!/bin/bash

# Set default username and password
username="user"
password="root"

# Set default Autostart value
Autostart=true

echo "Creating User and Setting it up"
sudo useradd -m "$username"
sudo adduser "$username" sudo
echo "$username:$password" | sudo chpasswd
sudo sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd
echo "User created and configured with username '$username' and password '$password'"

echo "Installing necessary packages"
sudo apt-get update
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install -y xfce4 desktop-base xfce4-terminal tightvncserver wget xscreensaver dbus-x11

echo "Applying Segfault & Systemd Bypass Patches..."
# 1. Bypass Systemctl checks that crash the daemon in Docker/Colab
sudo mv /usr/bin/systemctl /usr/bin/systemctl.bak 2>/dev/null
sudo bash -c 'echo "#!/bin/bash" > /usr/bin/systemctl'
sudo bash -c 'echo "exit 0" >> /usr/bin/systemctl'
sudo chmod +x /usr/bin/systemctl

# 2. Bypass Pipewire which causes the Segmentation Fault in headless Colab
sudo mv /usr/bin/pipewire /usr/bin/pipewire.bak 2>/dev/null
sudo bash -c 'echo "#!/bin/bash" > /usr/bin/pipewire'
sudo bash -c 'echo "sleep infinity" >> /usr/bin/pipewire'
sudo chmod +x /usr/bin/pipewire

echo "Installing Chrome Remote Desktop"
wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
sudo dpkg --install chrome-remote-desktop_current_amd64.deb
sudo apt-get install --assume-yes --fix-broken

echo "Setting up Desktop Environment"
sudo bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'
sudo apt-get remove --assume-yes gnome-terminal
sudo systemctl.bak disable lightdm.service 2>/dev/null

echo "Installing Google Chrome"
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg --install google-chrome-stable_current_amd64.deb
sudo apt-get install --assume-yes --fix-broken

# Prompt user for CRP value
read -p "Enter CRP value (from remotedesktop.google.com/headless): " CRP
read -p "Enter a 6-digit PIN: " Pin

echo "Finalizing"
if [ "$Autostart" = true ]; then
    mkdir -p "/home/$username/.config/autostart"
    link="https://youtu.be/d9ui27vVePY?si=TfVDVQOd0VHjUt_b"
    colab_autostart="[Desktop Entry]\nType=Application\nName=Colab\nExec=sh -c 'sensible-browser $link'\nIcon=\nComment=Open a predefined notebook at session signin.\nX-GNOME-Autostart-enabled=true"
    echo -e "$colab_autostart" | sudo tee "/home/$username/.config/autostart/colab.desktop"
    sudo chmod +x "/home/$username/.config/autostart/colab.desktop"
    sudo chown -R "$username:$username" "/home/$username/.config"
fi

sudo adduser "$username" chrome-remote-desktop

# Start DBus (required for XFCE to run properly without systemd)
sudo mkdir -p /var/run/dbus
sudo dbus-daemon --system --fork 2>/dev/null

# Register the host to Google
command="$CRP --pin=$Pin"
sudo su - "$username" -c "$command"

# Start the background service using INVOCATION_ID to explicitly bypass systemd Python checks
sudo su - "$username" -c "USER=$username INVOCATION_ID=1 /opt/google/chrome-remote-desktop/chrome-remote-desktop --start"

echo "========================================================"
echo "Finished Successfully! The segfault has been bypassed."
echo "You can now connect at https://remotedesktop.google.com"
echo "========================================================"

while true; do sleep 10; done

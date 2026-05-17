#!/bin/bash

# Set default username and password
username="user"
password="root"
Pin="123456"
Autostart=true

echo "Creating User and Setting it up..."
sudo useradd -m -s /bin/bash "$username" 2>/dev/null
echo "$username:$password" | sudo chpasswd

# FIX 1: Grant the user passwordless sudo so the Google Host script doesn't crash asking for a password
sudo usermod -aG sudo "$username"
echo "$username ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-$username >/dev/null
sudo chmod 0440 /etc/sudoers.d/90-$username

echo "Installing necessary packages..."
sudo apt-get update
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install -y xfce4 desktop-base xfce4-terminal tightvncserver wget xscreensaver dbus-x11 sudo curl procps

echo "Applying Systemctl Mock for Segfault.net containers..."
sudo mv /usr/bin/systemctl /usr/bin/systemctl.bak 2>/dev/null
sudo bash -c 'cat << "EOF" > /usr/bin/systemctl
#!/bin/bash
exit 0
EOF'
sudo chmod +x /usr/bin/systemctl

echo "Installing Chrome Remote Desktop..."
wget -q https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
# FIX 2: Use apt-get directly on the .deb file instead of dpkg to force dependency resolution
sudo apt-get install -y ./chrome-remote-desktop_current_amd64.deb

# Explicitly ensure the group exists (Fixes the "Group does not exist" fatal error)
sudo groupadd chrome-remote-desktop 2>/dev/null
sudo usermod -aG chrome-remote-desktop "$username"

echo "Setting up Desktop Environment..."
sudo bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'

echo "Installing Google Chrome..."
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt-get install -y ./google-chrome-stable_current_amd64.deb

echo "Finalizing Autostart..."
if [ "$Autostart" = true ]; then
    sudo mkdir -p "/home/$username/.config/autostart"
    # FIX 3: Use cat instead of echo -e so it writes cleanly regardless of the Linux shell
    sudo bash -c "cat << 'EOF' > /home/$username/.config/autostart/colab.desktop
[Desktop Entry]
Type=Application
Name=Colab
Exec=sh -c 'sensible-browser https://youtu.be/d9ui27vVePY?si=TfVDVQOd0VHjUt_b'
Icon=
Comment=Open a predefined notebook at session signin.
X-GNOME-Autostart-enabled=true
EOF"
    sudo chmod +x "/home/$username/.config/autostart/colab.desktop"
    sudo chown -R "$username:$username" "/home/$username/.config"
fi

# Prompt user for CRP value
echo ""
read -p "Enter CRP value (from remotedesktop.google.com/headless): " CRP

# Start DBus (required for XFCE to run properly without systemd)
sudo mkdir -p /var/run/dbus
sudo dbus-daemon --system --fork 2>/dev/null

echo "Registering Host..."
command="$CRP --pin=$Pin"
sudo su - "$username" -c "$command"

echo "Starting Background Service..."
# Start the background service manually bypassing systemd
sudo su - "$username" -c "USER=$username INVOCATION_ID=1 /opt/google/chrome-remote-desktop/chrome-remote-desktop --start"

echo "========================================================"
echo "Finished Successfully!"
echo "You can now connect at https://remotedesktop.google.com"
echo "========================================================"

while true; do sleep 10; done

#!/bin/bash

# Set DEBIAN_FRONTEND to noninteractive to suppress prompts
export DEBIAN_FRONTEND=noninteractive

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Function to create user
create_user() {
    echo "Please visit http://remotedesktop.google.com/headless and copy the command after Authentication"
    read -p "Paste the CRD SSH command here: " CRD
    
    username="disala"
    password="root"
    Pin="123456"
    
    echo "Creating User: $username"
    useradd -m -s /bin/bash "$username"
    adduser "$username" sudo
    echo "$username:$password" | chpasswd

    # Add PATH update to .bashrc
    echo 'export PATH=$PATH:/home/'"$username"'/.local/bin' >> /home/"$username"/.bashrc
}

# Extra storage setup (Fixed the "permission denied" error)
setup_storage() {
    local user=$1
    mkdir -p /storage
    chmod 777 /storage
    mkdir -p /home/"$user"/storage
    # Using sudo to ensure mount works
    mount --bind /storage /home/"$user"/storage
    chown -R "$user":"$user" /home/"$user"/storage
}

# Function to install and configure RDP
setup_rdp() {
    echo "Updating system..."
    apt update

    echo "Installing Google Chrome"
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    dpkg --install google-chrome-stable_current_amd64.deb || apt install --assume-yes --fix-broken
    
    echo "Installing Desktop Environment (GNOME)"
    # We install a slightly lighter version of Ubuntu Desktop to prevent crashes
    apt install --assume-yes ubuntu-desktop-minimal 
    apt install --assume-yes dbus-x11 xserver-xorg-video-dummy gnom-session-common

    echo "Installing Chrome Remote Desktop"
    wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    dpkg --install chrome-remote-desktop_current_amd64.deb || apt install --assume-yes --fix-broken

    echo "Configuring CRD for GNOME"
    # CRITICAL: This file tells CRD exactly how to start GNOME
    cat <<EOF > /etc/chrome-remote-desktop-session
export $(dbus-launch)
export DESKTOP_SESSION=ubuntu
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_TYPE=x11
exec gnome-session
EOF

    # Stop and disable the local display manager to prevent conflicts
    systemctl stop gdm3 || true
    systemctl disable gdm3 || true

    echo "Finalizing User Permissions"
    adduser "$username" chrome-remote-desktop
    
    # Run the CRD setup as the new user
    # Note: Using -l to ensure the full environment is loaded
    su -l "$username" -c "$CRD --pin=$Pin"

    # Fix for common CRD group issues
    usermod -aG video,render "$username"

    setup_storage "$username"
    service chrome-remote-desktop restart

    echo "RDP setup completed with Ubuntu Desktop"
}

# Execute functions
create_user
setup_rdp

# Keep-alive loop
echo "Starting keep-alive loop. Press Ctrl+C to stop."
while true; do
    echo "Host is running... $(date)"
    sleep 300
done

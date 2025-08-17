#!/bin/bash

# --- Configuration ---
# Set default username and password
readonly username="user"
readonly password="root"

# Set default Pin value
readonly Pin="123456"

# Set default Autostart value
readonly Autostart=true

# --- Script Logic ---

echo "Starting setup..."

# --- User Creation ---
echo "Checking for user '$username'..."
if ! id -u "$username" &>/dev/null; then
    echo "Creating User and Setting it up..."
    sudo useradd -m -s /bin/bash "$username"
    sudo adduser "$username" sudo
    echo "$username:$password" | sudo chpasswd
    echo "User '$username' created and configured with password '$password'."
else
    echo "User '$username' already exists. Skipping creation."
fi

# --- Package Installation ---
echo "Updating package lists..."
export DEBIAN_FRONTEND=noninteractive
sudo apt update

echo "Installing Ubuntu Desktop and necessary packages..."
sudo apt install --assume-yes ubuntu-desktop wget

# --- Google Chrome Installation ---
echo "Checking for Google Chrome..."
if ! command -v google-chrome &>/dev/null; then
    echo "Installing Google Chrome..."
    if [ ! -f "google-chrome-stable_current_amd64.deb" ]; then
        wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    fi
    sudo dpkg --install google-chrome-stable_current_amd64.deb
    sudo apt install --assume-yes --fix-broken
else
    echo "Google Chrome is already installed."
fi

# --- Chrome Remote Desktop Installation ---
echo "Checking for Chrome Remote Desktop..."
if ! dpkg -l | grep -q "chrome-remote-desktop"; then
    echo "Installing Chrome Remote Desktop..."
    if [ ! -f "chrome-remote-desktop_current_amd64.deb" ]; then
        wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    fi
    sudo dpkg --install chrome-remote-desktop_current_amd64.deb
    sudo apt install --assume-yes --fix-broken
else
    echo "Chrome Remote Desktop is already installed."
fi

# --- System Configuration ---
echo "Configuring display manager and session..."
sudo systemctl disable gdm3.service

if [ ! -f "/etc/chrome-remote-desktop-session" ]; then
    echo "Configuring Chrome Remote Desktop to use the GNOME session..."
    sudo tee /etc/chrome-remote-desktop-session > /dev/null <<EOL
export XDG_SESSION_TYPE=x11
export GNOME_SHELL_SESSION_MODE=ubuntu
exec /usr/bin/gnome-session
EOL
else
    echo "Chrome Remote Desktop session file already configured."
fi

# --- Autostart Configuration ---
if [ "$Autostart" = true ]; then
    autostart_file="/home/$username/.config/autostart/colab.desktop"
    echo "Checking for autostart configuration..."
    if [ ! -f "$autostart_file" ]; then
        echo "Creating autostart file..."
        mkdir -p "/home/$username/.config/autostart"
        link="https://youtu.be/d9ui27vVePY?si=TfVDVQOd0VHjUt_b"
        colab_autostart="[Desktop Entry]\nType=Application\nName=Colab\nExec=sh -c 'sensible-browser $link'\nIcon=\nComment=Open a predefined notebook at session signin.\nX-GNOME-Autostart-enabled=true"
        echo -e "$colab_autostart" | sudo tee "$autostart_file"
        sudo chmod +x "$autostart_file"
        sudo chown "$username:$username" "/home/$username/.config" -R
        echo "Autostart file created."
    else
        echo "Autostart file already exists."
    fi
fi

# --- Finalizing Chrome Remote Desktop Setup ---
# A flag file is used to ensure the CRP command is only run once.
setup_flag="/home/$username/.crd_setup_complete"

if [ ! -f "$setup_flag" ]; then
    echo "Finalizing Chrome Remote Desktop Setup for the first time..."

    # Prompt user for CRP value
    read -p "Enter your Chrome Remote Desktop authorization key (CRP): " CRP

    sudo adduser "$username" chrome-remote-desktop
    command="$CRP --pin=$Pin"

    echo "Starting Chrome Remote Desktop service for user $username..."
    sudo su - "$username" -c "$command"
    
    # Create the flag file to indicate setup is complete
    sudo touch "$setup_flag"
    sudo chown "$username:$username" "$setup_flag"
else
    echo "Chrome Remote Desktop has already been configured for this user."
fi

# --- Service Management ---
echo "Ensuring Chrome Remote Desktop service is running..."
sudo service chrome-remote-desktop start

echo "Finished Successfully. The remote desktop should be available shortly."
# The infinite loop is generally used to keep a container running.
# You may remove it if this script is not the main process in a container.
while true; do sleep 3600; done

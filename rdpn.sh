#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# ==========================================
# 1. Environment and Base Packages
# ==========================================
export DEBIAN_FRONTEND=noninteractive

echo "Updating and upgrading packages..."
apt-get update
apt-get upgrade --assume-yes

echo "Installing base dependencies..."
apt-get install --assume-yes \
    curl gpg wget sudo apt-utils xvfb xfce4 xbase-clients desktop-base \
    vim xscreensaver python-psutil psmisc python3-psutil \
    xserver-xorg-video-dummy ffmpeg python3-packaging \
    python3-xdg libutempter0 firefox

# ==========================================
# 2. Add Microsoft & Google Repositories
# ==========================================
echo "Adding Microsoft GPG keys and repo..."
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
mv /tmp/microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
echo "deb [arch=amd64] http://packages.microsoft.com/repos/vscode stable main" | tee /etc/apt/sources.list.d/vs-code.list

echo "Adding Google Chrome GPG keys and repo..."
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list

# ==========================================
# 3. Install Google Chrome & Chrome Remote Desktop
# ==========================================
echo "Installing Google Chrome and Chrome Remote Desktop..."
apt-get update
apt-get install --assume-yes google-chrome-stable

wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
# dpkg might fail due to missing dependencies, so we catch it and use fix-broken
dpkg --install chrome-remote-desktop_current_amd64.deb || apt-get install --assume-yes --fix-broken
rm chrome-remote-desktop_current_amd64.deb

# Set the default X session for Chrome Remote Desktop
echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session

# ==========================================
# 4. User Configuration
# ==========================================
echo "Setting root password to 'epicminer'..."
echo 'root:epicminer' | chpasswd

TARGET_USER="myuser"

echo "Creating user '$TARGET_USER'..."
if ! id "$TARGET_USER" &>/dev/null; then
    adduser --disabled-password --gecos '' "$TARGET_USER"
fi

# Ensure home directory exists and permissions are set
mkhomedir_helper "$TARGET_USER" || true

echo "Configuring sudo privileges and groups..."
adduser "$TARGET_USER" sudo
# Safely add NOPASSWD to sudoers instead of directly appending to /etc/sudoers
echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99_nopasswd
chmod 0440 /etc/sudoers.d/99_nopasswd

usermod -aG chrome-remote-desktop "$TARGET_USER"

# ==========================================
# 5. User-level Chrome Remote Desktop setup
# ==========================================
USER_HOME=$(eval echo "~$TARGET_USER")

echo "Creating user Chrome Remote Desktop config directories..."
mkdir -p "$USER_HOME/.config/chrome-remote-desktop"
touch "$USER_HOME/.config/chrome-remote-desktop/host.json"

echo "/usr/bin/pulseaudio --start" > "$USER_HOME/.chrome-remote-desktop-session"
echo "startxfce4 :1030" >> "$USER_HOME/.chrome-remote-desktop-session"

# Fix ownership for the created files
chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.chrome-remote-desktop-session"
chmod a+rx "$USER_HOME/.config/chrome-remote-desktop"

# ==========================================
# 6. Generate the Startup Script (Replaces CMD)
# ==========================================
START_SCRIPT="$USER_HOME/start-crd.sh"

cat << 'EOF' > "$START_SCRIPT"
#!/bin/bash
if [ -z "$CODE" ] || [ -z "$PIN" ] || [ -z "$HOSTNAME" ]; then 
    echo "Error: CODE, PIN, and HOSTNAME environment variables must be set."
    echo "Usage: CODE=\"4/xxx\" PIN=\"123456\" HOSTNAME=\"MyServer\" ./start-crd.sh"
    exit 1
fi

# Start the host
DISPLAY= /opt/google/chrome-remote-desktop/start-host --code="$CODE" --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name="$HOSTNAME" --pin="$PIN"

# Rename the host file with its MD5 hash equivalent
HOST_HASH=$(echo -n "$HOSTNAME" | md5sum | cut -c -32)
FILENAME="$HOME/.config/chrome-remote-desktop/host#${HOST_HASH}.json"

echo "Saving config to $FILENAME"
cp "$HOME/.config/chrome-remote-desktop/host#"*.json "$FILENAME" 2>/dev/null || true

# Restart the service
sudo service chrome-remote-desktop stop
sudo service chrome-remote-desktop start

echo "Chrome Remote Desktop is successfully running with HOSTNAME: $HOSTNAME"
EOF

chmod +x "$START_SCRIPT"
chown "$TARGET_USER:$TARGET_USER" "$START_SCRIPT"

echo "=========================================="
echo "Server Transformation Complete!"
echo "To start Chrome Remote Desktop, run the following:"
echo "1. Switch to the user:  su - $TARGET_USER"
echo "2. Run the start script with your credentials:"
echo "   CODE=\"4/your-auth-code\" PIN=\"123456\" HOSTNAME=\"your-hostname\" ./start-crd.sh"
echo "=========================================="

import os
import sys
import subprocess
import time
import shutil
import json
from datetime import datetime, timedelta

# === CONFIGURATION ===
NGROK_AUTH_TOKEN = input("your auth token :")
RDP_PORT = 3389
USER_NAME = "rdpuser"
PASSWORD = "root"
AUTOSTART = False

# URLs in exact sequence with waits
URL_FIRST = ""
URL_SECOND = ""
WAIT_FIRST_URL_SECONDS = 15

# === ANSI COLORS & EMOJIS ===
class LogColors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    INFO = "\033[94m"
    WARN = "\033[93m"
    ERROR = "\033[91m"
    SUCCESS = "\033[92m"
    HEARTBEAT = "\033[95m"

EMOJIS = {
    "INFO": "ℹ️",
    "WARN": "⚠️",
    "ERROR": "❌",
    "SUCCESS": "✅",
    "START": "🚀",
    "STOP": "🛑",
    "DOWNLOAD": "⬇️",
    "INSTALL": "📦",
    "USER": "👤",
    "FIREWALL": "🔥",
    "BROWSER": "🌐",
    "HEARTBEAT": "❤️‍🔥",
    "WALLPAPER": "🖼️",
    "EXTENSION": "🔌",
}

def log(msg, level="INFO"):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    color = LogColors.INFO
    emoji = EMOJIS["INFO"]
    if level == "WARN":
        color = LogColors.WARN
        emoji = EMOJIS["WARN"]
    elif level == "ERROR":
        color = LogColors.ERROR
        emoji = EMOJIS["ERROR"]
    elif level == "SUCCESS":
        color = LogColors.SUCCESS
        emoji = EMOJIS["SUCCESS"]
    elif level == "HEARTBEAT":
        color = LogColors.HEARTBEAT + LogColors.BOLD
        emoji = EMOJIS["HEARTBEAT"]
    elif level == "START":
        color = LogColors.BOLD
        emoji = EMOJIS["START"]
    elif level == "STOP":
        color = LogColors.ERROR
        emoji = EMOJIS["STOP"]
    elif level == "INSTALL":
        color = LogColors.INFO
        emoji = EMOJIS["INSTALL"]
    elif level == "WALLPAPER":
        color = LogColors.INFO
        emoji = EMOJIS["WALLPAPER"]
    elif level == "EXTENSION":
        color = LogColors.INFO
        emoji = EMOJIS["EXTENSION"]
    print(f"{color}{LogColors.BOLD}{now} {emoji} [{level}] {msg}{LogColors.RESET}", flush=True)

def run(cmd, check=True, capture_output=True):
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    log(f"Executing: {cmd}", "INFO")
    try:
        completed = subprocess.run(
            cmd,
            shell=True,
            check=check,
            text=True,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.STDOUT if capture_output else None,
            env=env,
        )
        out = completed.stdout.strip() if completed.stdout else ""
        if out:
            lines = out.splitlines()
            if len(lines) > 10:
                truncated = "\n".join(lines[:5] + ["... (truncated) ..."] + lines[-3:])
                log(f"OUTPUT (truncated):\n{truncated}", "INFO")
            else:
                log(f"OUTPUT:\n{out}", "INFO")
        return out
    except subprocess.CalledProcessError as e:
        log(f"Command failed (exit {e.returncode}): {e}", "ERROR")
        if check:
            sys.exit(1)
        return ""

def user_exists(username):
    try:
        subprocess.run(f"id -u {username}", shell=True, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except subprocess.CalledProcessError:
        return False

def create_user(username):
    if user_exists(username):
        log(f"User '{username}' exists. Resetting password.", "WARN")
        run(f"echo '{username}:{PASSWORD}' | chpasswd")
        return PASSWORD

    log(f"Creating user '{username}'.", "INSTALL")
    run(f"useradd -m -s /bin/bash {username}")
    run(f"echo '{username}:{PASSWORD}' | chpasswd")

    # Add the user to sudo group
    run(f"usermod -aG sudo {username}")

    run(f"chmod 700 /home/{username}")
    log(f"User '{username}' created with password set and added to sudo group.", "SUCCESS")
    return PASSWORD


def is_systemd_running():
    try:
        with open("/proc/1/comm", "r") as f:
            return f.read().strip() == "systemd"
    except Exception:
        return False

def install_packages():
    log("Updating package lists and upgrading packages...", "INSTALL")
    run("apt-get update -q -y")
    run("apt-get upgrade -q -y")
    packages = [
        "xfce4", "desktop-base", "xfce4-terminal", "xscreensaver",
        "xrdp", "telegram-desktop", "qbittorrent", "curl",
        "unzip", "wget", "sudo", "ufw"
    ]
    log(f"Installing packages: {', '.join(packages)}", "INSTALL")
    run(f"apt-get install -q -y {' '.join(packages)}")

def install_chrome():
    log("Installing Google Chrome...", "INSTALL")
    run("wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome.deb")
    run("dpkg -i /tmp/google-chrome.deb || true")
    run("apt-get install -f -q -y")
    log("Google Chrome installed.", "SUCCESS")

def install_chrome_extensions():
    log("Configuring Google Chrome extensions policy...", "EXTENSION")
    if not shutil.which("google-chrome"):
        log("Google Chrome executable not found. Cannot install extensions.", "ERROR")
        sys.exit(1)

    POLICY_DIR = "/etc/opt/chrome/policies/managed"
    POLICY_FILE = os.path.join(POLICY_DIR, "enigmano_extensions.json")
    os.makedirs(POLICY_DIR, exist_ok=True)

    extensions = [
        "bkmmlbllpjdpgcgdohbaghfaecnddhni;https://clients2.google.com/service/update2/crx",
        "hlbopkdbimgihmpcaohopplcbpanmjlb;https://clients2.google.com/service/update2/crx",
        "kijgnjhogkjodpakfmhgleobifempckf;https://clients2.google.com/service/update2/crx",
        "jplgfhpmjnbigmhklmmbgecoobifkmpa;https://clients2.google.com/service/update2/crx",
        "bhnhbmjfaanopkalgkjoiemhekdnhanh;https://clients2.google.com/service/update2/crx",
        "nlkaejimjacpillmajjnopmpbkbnocid;https://clients2.google.com/service/update2/crx",
    ]

    policy_data = {
        "ExtensionInstallForcelist": extensions
    }

    with open(POLICY_FILE, "w") as f:
        json.dump(policy_data, f, indent=2)

    log(f"Extension policy saved to {POLICY_FILE}.", "SUCCESS")
    log("Extensions will install silently on next Chrome launch.", "SUCCESS")

def launch_chrome_and_wait_then_close(user):
    log("Launching Chrome to trigger extension installation...", "EXTENSION")
    proc = subprocess.Popen(
        ["sudo", "-u", user, "google-chrome", "--no-first-run", "--no-default-browser-check", "about:blank"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    log("Chrome launched. Waiting 15 seconds for extensions to install...", "EXTENSION")
    time.sleep(15)
    proc.terminate()
    proc.wait(timeout=10)
    log("Chrome closed after extension installation wait.", "EXTENSION")

def configure_xrdp():
    log("Configuring XRDP and XFCE session...", "INSTALL")
    session_content = "startxfce4\n"
    paths = [f"/etc/skel/.xsession", f"/root/.xsession", f"/home/{USER_NAME}/.xsession"]
    for path in paths:
        try:
            with open(path, "w") as f:
                f.write(session_content)
            run(f"chown {USER_NAME}:{USER_NAME} {path}", check=False)
        except Exception as e:
            log(f"Failed to write .xsession at {path}: {e}", "WARN")

    if is_systemd_running():
        for attempt in range(5):
            log(f"Enabling and starting xrdp service (attempt {attempt+1})...", "INSTALL")
            result = subprocess.run("systemctl enable xrdp --now", shell=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode == 0:
                log("xrdp service started successfully.", "SUCCESS")
                break
            time.sleep(2)
        else:
            log("Failed to start xrdp service after retries.", "ERROR")
            sys.exit(1)
    else:
        log("Systemd not detected; starting xrdp using service command.", "WARN")
        run("service xrdp start", check=False)

    log("Configuring firewall to allow RDP port...", "FIREWALL")
    status = run("ufw status", check=False)
    if "inactive" in status.lower():
        run("ufw --force enable")
    run(f"ufw allow {RDP_PORT}/tcp")
    log("Firewall rules updated.", "SUCCESS")

def install_ngrok():
    if shutil.which("ngrok"):
        log("ngrok is already installed.", "INFO")
        return
    log("Downloading and installing ngrok...", "INSTALL")
    run("wget -q -O /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-stable-linux-amd64.zip")
    run("unzip -o /tmp/ngrok.zip -d /usr/local/bin/")
    run("chmod +x /usr/local/bin/ngrok")
    log("ngrok installed.", "SUCCESS")

def configure_ngrok_auth():
    log("Configuring ngrok auth token...", "INSTALL")
    run(f"/usr/local/bin/ngrok config add-authtoken {NGROK_AUTH_TOKEN}")

def start_ngrok():
    log("Starting ngrok TCP tunnel for RDP port...", "INSTALL")
    proc = subprocess.Popen(f"/usr/local/bin/ngrok tcp {RDP_PORT} --log=stdout", shell=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return proc

def get_ngrok_tunnel_url(proc, timeout=30):
    start = time.time()
    while True:
        if proc.poll() is not None:
            log("ngrok process exited unexpectedly.", "ERROR")
            return None
        line = proc.stdout.readline()
        if line:
            line = line.strip()
            if "url=" in line:
                idx = line.find("url=")
                url = line[idx+4:].split()[0]
                if url.startswith("tcp://"):
                    log(f"ngrok tunnel established: {url}", "SUCCESS")
                    return url[len("tcp://"):]
        if time.time() - start > timeout:
            log("Timeout waiting for ngrok tunnel URL.", "ERROR")
            return None

def changewall():
    log("Changing wallpaper...", "WALLPAPER")
    wallpaper_url = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTguTYOsGU1Fp773FzNpwJ4HOi6lqh7TTdBceBGgfRBfHC8J10GWzivcSw&s=10"
    local_filename = "xfce-verticals.png"
    destination_path = "/usr/share/backgrounds/xfce/"
    try:
        run(f"curl -s -L -k -o {local_filename} {wallpaper_url}")
        if not os.path.exists(local_filename):
            log("Wallpaper download failed: file not found.", "ERROR")
            return
        os.makedirs(destination_path, exist_ok=True)
        shutil.copy(local_filename, destination_path)
        run(f"chmod 644 {os.path.join(destination_path, local_filename)}")
        log("✅ Wallpaper changed and copied successfully.", "SUCCESS")
    except Exception as e:
        log(f"Failed to change wallpaper: {e}", "ERROR")

def configure_autostart(username):
    if not AUTOSTART:
        log("Autostart disabled by config.", "WARN")
        return
    autostart_dir = f"/home/{username}/.config/autostart"
    os.makedirs(autostart_dir, exist_ok=True)

    first_desktop = f"""[Desktop Entry]
Type=Application
Exec=google-chrome --no-first-run --no-default-browser-check --new-window {URL_FIRST}
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=ChromeFirstURL
Comment=Open first URL at startup
"""

    second_desktop = f"""[Desktop Entry]
Type=Application
Exec=sh -c 'sleep {WAIT_FIRST_URL_SECONDS}; google-chrome --no-first-run --no-default-browser-check --new-window "{URL_SECOND}"'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=ChromeSecondURL
Comment=Open second URL at startup after delay
"""

    first_path = os.path.join(autostart_dir, "chrome_first_url.desktop")
    second_path = os.path.join(autostart_dir, "chrome_second_url.desktop")

    with open(first_path, "w") as f:
        f.write(first_desktop)
    with open(second_path, "w") as f:
        f.write(second_desktop)

    run(f"chown -R {username}:{username} {autostart_dir}")
    run(f"chmod +x {first_path} {second_path}")
    log("Configured Chrome autostart URLs with precise timing.", "SUCCESS")

def heartbeat_loop():
    log("Entering heartbeat loop. Logging every 10 minutes.", "HEARTBEAT")
    start_time = datetime.now()
    try:
        while True:
            elapsed = datetime.now() - start_time
            hours, remainder = divmod(elapsed.total_seconds(), 3600)
            minutes, seconds = divmod(remainder, 60)
            uptime_str = f"{int(hours):02}:{int(minutes):02}:{int(seconds):02}"
            log(f"Heartbeat: Script running. Total uptime {uptime_str}", "HEARTBEAT")
            time.sleep(600)  # 10 minutes
    except KeyboardInterrupt:
        log("Heartbeat loop terminated by user.", "STOP")
        sys.exit(0)

def main():
    log("Starting setup operation.", "START")

    # 1. User creation/reset
    create_user(USER_NAME)

    # 2. Package install
    install_packages()

    # 3. Chrome install
    install_chrome()

    # 4. Chrome extensions policy
    install_chrome_extensions()

    # 5. Launch Chrome once, wait, then close to trigger extensions install
    launch_chrome_and_wait_then_close(USER_NAME)

    # 6. XRDP setup and firewall
    configure_xrdp()

    # 7. Change wallpaper
    changewall()

    # 8. Configure autostart URLs with wait
    configure_autostart(USER_NAME)

    # 9. Install ngrok and start tunnel
    install_ngrok()
    configure_ngrok_auth()
    ngrok_proc = start_ngrok()

    # 10. Print ngrok tunnel info with retry
    tunnel_url = None
    for _ in range(30):
        tunnel_url = get_ngrok_tunnel_url(ngrok_proc)
        if tunnel_url:
            break
        time.sleep(1)

    if tunnel_url:
        log(f"ngrok tunnel ready: {tunnel_url}", "SUCCESS")
        print("\n==== 🔥 NGROK RDP ACCESS 🔥 ====")
        print(f"User: {USER_NAME}")
        print(f"Password: {PASSWORD}")
        print(f"Tunnel TCP Host:Port -> {tunnel_url}\n")
    else:
        log("Failed to retrieve ngrok tunnel URL. Exiting.", "ERROR")
        ngrok_proc.terminate()
        sys.exit(1)

    # 11. Enter heartbeat loop indefinitely
    heartbeat_loop()

if __name__ == "__main__":
    main()

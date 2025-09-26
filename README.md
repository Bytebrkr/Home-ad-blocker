# Home-ad-blocker

# Pi-hole Docker Manager 🧱🕳️

A user-friendly, interactive Bash script to **install, manage, and monitor Pi-hole using Docker**.  
---

## 🚀 Features

- ✅ One-command Pi-hole Docker installation
- 🔁 Start, stop, restart, or update the Pi-hole container
- 📊 View container status, IP, memory usage, and stats
- 🔐 Secure auto-generated admin password
- 🔍 View live logs
- 🧹 Safe uninstall option with optional data cleanup
- 📦 Automatically installs Docker if missing
- 🛑 Prevents running as root for safety

---

## 🛠️ Requirements

- **Linux OS** (Ubuntu, Debian, Fedora, etc.)
- **Docker** and **Docker Compose plugin**
- **Ports 53, 67, and 80 must be available**
- **Non-root user** with `sudo` privileges

---

## 📥 Quick Start

```bash
# Download and make executable
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/pihole-manager.sh
chmod +x pihole-manager.sh

# Run the installer
./pihole-manager.sh install

```
---

## 📦 Script Usage
```bash./pihole-manager.sh [OPTION]```
### Available Options
- ```Install``` Install Pi-hole with Docker
- ```status``` Show Pi-hole status and information
- ```start``` Start Pi-hole container
- ```stop``` Stop Pi-hole container
- ```restart``` Restart Pi-hole container
- ```update``` Update Pi-hole Docker image
- ```logs``` Show Pi-hole logs
- ```Uninstall``` Remove Pi-hole container and data
- ```help``` Show this help message


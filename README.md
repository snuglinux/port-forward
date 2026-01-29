# Port Forward Manager 🔄

A universal port forwarding solution using socat with systemd integration, multi-language support, and comprehensive logging. Perfect for forwarding ports to virtual machines, containers, or remote services.

## ✨ Features

- ✅ **Simple Configuration**: Easy-to-edit configuration files for port mappings
- ✅ **TCP & UDP Support**: Forward both TCP and UDP connections
- ✅ **Multi-language Interface**: English and Ukrainian interfaces with auto-detection
- ✅ **Systemd Integration**: Runs as a system service with auto-restart
- ✅ **Logging with Rotation**: Comprehensive logging with automatic log rotation
- ✅ **Security-First**: Runs as unprivileged user with minimal capabilities
- ✅ **Port Range Support**: Configure multiple ports easily
- ✅ **Privileged Port Support**: Works with ports below 1024 using capabilities
- ✅ **Health Monitoring**: Built-in status checking and process management
- ✅ **Easy Management**: Simple commands for start, stop, restart, and status

## 📦 Installation

### Quick Install (All Distributions)

```bash
git clone https://github.com/yourusername/port-forward.git
cd port-forward
sudo ./install.sh

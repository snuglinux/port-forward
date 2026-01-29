# Port Forward Manager 🔄

A lightweight port forwarding manager based on **socat** with **systemd integration**, **multi-language output**, and **log rotation**.  
Perfect for forwarding ports to **VMs, containers, lab networks, VPN peers**, or **remote services**.

---

## ✨ Features

- ✅ **Simple configuration** via `/etc/port-forward/ports.conf`
- ✅ **TCP & UDP forwarding**
- ✅ **Systemd service** with auto-restart support
- ✅ **Multi-language output** (English / Ukrainian) with auto-detection
- ✅ **Logging with rotation** (`/var/log/port-forward`)
- ✅ **Security-first design**
  - can run as **unprivileged user**
  - supports privileged ports with capabilities
- ✅ **Status and process management** via PID files

---

## 📦 Installation

### Quick Install (All Distributions)

```bash
git clone https://github.com/snuglinux/port-forward.git
cd port-forward
sudo ./install.sh
```

This installs:

- Script: `/usr/bin/port-forward.sh`
- Service: `/etc/systemd/system/port-forward.service`
- Config dir: `/etc/port-forward/`
- Locales: `/usr/share/port-forward/locale/`

---

## ✅ Requirements

Required:

- `socat`

Optional (only for JSON translations):

- `jq`

> **Note:** `jq` is used only for reading localized messages from `locale/*.json`.  
> Forwarding itself does not technically require `jq` if fallback mode is implemented.

---

## ⚙️ Configuration

### Main config file

`/etc/port-forward/port-forward.conf`

Example:

```ini
LOGGING_ENABLED=true
LOG_FILE=/var/log/port-forward/port-forward.log

LANGUAGE=AUTO

SOCAT_PATH=/usr/bin/socat
EXTRA_SOCAT_OPTS=

CHECK_PORTS_BEFORE_START=true
AUTO_RESTART=true

MIN_UNPRIVILEGED_PORT=1024
REQUIRED_CAPABILITIES=CAP_NET_BIND_SERVICE
```

---

## 🔀 Ports configuration (`ports.conf`)

**This file is required.**  
If it does not exist, the service will fail with:

```
no_ports_file: /etc/port-forward/ports.conf
```

Path:

```
/etc/port-forward/ports.conf
```

Format:

```
<local_port> <destination_ip:port> [tcp|udp]
```

Examples:

```conf
# TCP forward: local 2277 -> 10.77.77.2:22
2277 10.77.77.2:22 tcp

# UDP forward: local 1194 -> 10.77.77.2:1194
1194 10.77.77.2:1194 udp
```

---

## ▶️ Usage

### Run manually

```bash
sudo /usr/bin/port-forward.sh start
sudo /usr/bin/port-forward.sh status
sudo /usr/bin/port-forward.sh stop
```

Shortcut (default action = start):

```bash
sudo /usr/bin/port-forward.sh
```

---

## 🧩 Systemd

### Enable and start service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now port-forward.service
```

### Check logs

```bash
journalctl -u port-forward.service -e --no-pager
```

---

## 🔒 Running as unprivileged user (recommended)

To run the service as:

```ini
User=portforward
Group=portforward
```

you must ensure system directories exist with correct permissions.

### Create service user

```bash
sudo useradd -r -s /usr/sbin/nologin -d /nonexistent portforward 2>/dev/null || true
```

### Ensure config and ports file are readable

```bash
sudo mkdir -p /etc/port-forward
sudo chmod 755 /etc/port-forward
sudo chmod 644 /etc/port-forward/ports.conf
```

### Ensure log directory is writable

```bash
sudo mkdir -p /var/log/port-forward
sudo chown -R portforward:portforward /var/log/port-forward
sudo chmod 755 /var/log/port-forward
```

### Recommended systemd settings for runtime directories

Add to `port-forward.service`:

```ini
[Service]
User=portforward
Group=portforward

RuntimeDirectory=port-forward
RuntimeDirectoryMode=0755

LogsDirectory=port-forward
LogsDirectoryMode=0755
```

This prevents errors like:

```
Failed to set up mount namespacing: /run/port-forward: No such file or directory
Failed at step NAMESPACE spawning ...
```

---

## 🌐 Firewall notes

If you want to access forwarded ports **from another machine**, you must allow them in firewall.

Example (firewalld):

```bash
sudo firewall-cmd --add-port=2277/tcp
sudo firewall-cmd --add-port=2277/tcp --permanent
sudo firewall-cmd --reload
```

---

## ✅ Testing

### Check port is listening

```bash
ss -tlnp | grep ':2277 '
```

Expected output example:

```
LISTEN ... 0.0.0.0:2277 ... users:(("socat",pid=70693,fd=5))
```

### Test connectivity to destination

```bash
nc -vz 10.77.77.2 22
```

### Test forwarded port locally

```bash
nc -vz 127.0.0.1 2277
ssh -p 2277 user@127.0.0.1
```

### Test forwarded port from another host

```bash
nc -vz <HOST_IP> 2277
ssh -p 2277 user@<HOST_IP>
```

---

## 🛠 Troubleshooting

### 1) Service restart loop / “Start request repeated too quickly”

Cause: service exits with failure too fast (for example missing `ports.conf`).

Fix:

```bash
sudo systemctl reset-failed port-forward.service
```

Also make sure `/etc/port-forward/ports.conf` exists.

---

### 2) `no_ports_file: /etc/port-forward/ports.conf`

Create config:

```bash
sudo tee /etc/port-forward/ports.conf >/dev/null <<'EOF'
2277 10.77.77.2:22 tcp
EOF
sudo chmod 0644 /etc/port-forward/ports.conf
```

---

### 3) `jq not found`

If you installed without `jq`, translations will not work.

Install it:

- Debian/Ubuntu:
  ```bash
  sudo apt install jq
  ```
- Arch:
  ```bash
  sudo pacman -S jq
  ```
- Fedora:
  ```bash
  sudo dnf install jq
  ```

Or modify script to fall back to default keys when `jq` is missing.

---

### 4) Privileged ports (<1024)

For ports like 80/443, systemd may require:

```ini
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

---

## 📄 License

MIT (or specify your preferred license here)


## 👤 System user and directories (systemd-sysusers + systemd-tmpfiles)

Instead of creating the `portforward` user and directories manually, you can delegate this to systemd.

### sysusers

Install `/usr/lib/sysusers.d/port-forward.conf`:

```ini
u portforward - "Port Forward Manager" /nonexistent /usr/sbin/nologin
g portforward -
m portforward portforward
```

Apply:

```bash
sudo systemd-sysusers
```

### tmpfiles

Install `/usr/lib/tmpfiles.d/port-forward.conf`:

```ini
d /run/port-forward 0755 portforward portforward -
d /var/log/port-forward 0755 portforward portforward -
```

Apply:

```bash
sudo systemd-tmpfiles --create
```

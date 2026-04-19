# Homelab

Raspberry Pi 4 home server configuration.

## Services

| Service | Port | Local URL |
|---------|------|-----------|
| Pi-hole | 8080 (HTTP), 8443 (HTTPS) | pihole.robertson-walker.me/admin/ |
| Nginx Proxy Manager | 81 | npm.robertson-walker.me |
| Paperless-ngx | 8010 | paperless.robertson-walker.me |
| Portainer | 9000 | portainer.robertson-walker.me |
| Watchtower | - | (no UI, auto-updates containers daily) |

## Architecture

Local domain routing works in two steps:

1. **Pi-hole DNS** resolves domain to IP
   - `*.robertson-walker.me` → `192.168.178.111`
   - Configured in `pihole/custom.list`

2. **Nginx Proxy Manager** routes by subdomain to correct port
   - `paperless.robertson-walker.me` → `paperless:8000`
   - `portainer.robertson-walker.me` → `portainer:9000`
   - `pihole.robertson-walker.me` → `192.168.178.111:8443` (HTTPS)

**Request flow:**

```
Browser: paperless.robertson-walker.me
   │
   ▼
Pi-hole: resolves to 192.168.178.111
   │
   ▼
Browser connects to 192.168.178.111:80
   │
   ▼
NPM: sees "paperless" subdomain, proxies to paperless:8000
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | All service definitions |
| `.env` | Secrets (not in git) |
| `.env.example` | Template for secrets |
| `pihole/custom.list` | Local DNS entries |

## Usage

```bash
# Start all services
cd ~/homelab
sudo docker compose up -d

# View logs
sudo docker compose logs -f [service]

# Restart a service
sudo docker compose restart [service]

# Update all containers (Watchtower does this automatically)
sudo docker compose pull
sudo docker compose up -d
```

## Disk Layout

| Mount | Device | Label | Purpose |
|-------|--------|-------|---------|
| `/mnt/ssd/system` | SSD 122GB | system | Docker data, logs |
| `/mnt/ssd/data` | SSD 745GB | data | Personal data (ETH stuff) |
| `/mnt/hdd/timemachine` | HDD 1.6TB | backups | macOS Time Machine backups |
| `/mnt/hdd/storage` | HDD 2TB | hdd_data | Paperless consume, backups |

### Bind Mounts (fstab)

```
/var/log        → /mnt/ssd/system/var/log        (logs on SSD, not SD card)
/var/lib/docker → /mnt/ssd/system/var/lib/docker (Docker data on SSD)
```

### fstab Configuration

```
# SSD Mounts (failsafe)
LABEL=system    /mnt/ssd/system       ext4  defaults,noatime,nofail,x-systemd.device-timeout=10s  0  2
LABEL=data      /mnt/ssd/data         ext4  defaults,noatime,nofail,x-systemd.device-timeout=10s  0  2

# HDD Mounts (failsafe, longer timeout for spinup)
LABEL=backups   /mnt/hdd/timemachine  ext4  defaults,noatime,nofail,x-systemd.device-timeout=30s  0  2
LABEL=hdd_data  /mnt/hdd/storage      ext4  defaults,noatime,nofail,x-systemd.device-timeout=30s  0  2

# Bind Mounts (Docker & Logs on SSD)
/mnt/ssd/system/var/log         /var/log         none  bind,nofail,x-systemd.requires-mounts-for=/mnt/ssd/system  0  0
/mnt/ssd/system/var/lib/docker  /var/lib/docker  none  bind,nofail,x-systemd.requires-mounts-for=/mnt/ssd/system  0  0
```

## Failsafe Design

- All disk mounts use `nofail` in fstab — system boots even if disks fail
- `x-systemd.device-timeout` prevents hanging on missing disks
- Logs write to SSD, not SD card (prevents SD card wear)
- Docker data on SSD with bind mount from `/var/lib/docker`
- Configs in `~/homelab/` are git-tracked for easy recovery

## Network Configuration

- **Pi IP:** 192.168.178.111
- **DNS:** Pi-hole listens on port 53
- **Pi-hole listening mode:** ALL (required for Docker networking)

For devices to use local domains, they must use Pi-hole as their DNS server.
Configure your router's DHCP to assign `192.168.178.111` as the DNS server.

## Backup Strategy

### What's backed up where

| Component | Backup Location |
|-----------|-----------------|
| Service configs | Git (this repo) |
| Secrets (.env) | Password manager |
| Docker volumes | `/mnt/hdd/storage/backups/` |
| NPM proxy hosts | Documented below |

### NPM Proxy Host Configuration

| Domain | Scheme | Forward Host | Forward Port |
|--------|--------|--------------|--------------|
| paperless.robertson-walker.me | http | paperless | 8000 |
| portainer.robertson-walker.me | http | portainer | 9000 |
| pihole.robertson-walker.me | https | 192.168.178.111 | 8443 |
| npm.robertson-walker.me | http | nginx-proxy-manager | 81 |

### Manual volume backup

```bash
# Stop containers, backup, restart
cd ~/homelab
sudo docker compose stop
sudo rsync -av /var/lib/docker/volumes/ /mnt/hdd/storage/backups/docker-volumes-$(date +%Y%m%d)/
sudo docker compose up -d
```

## HDD Power Management

HDDs spin down after 30 minutes of inactivity to reduce wear and noise.

```bash
# Check disk power state
sudo hdparm -C /dev/sdX

# Manually spin down
sudo hdparm -y /dev/sdX
```

Configuration is set via udev rule in `/etc/udev/rules.d/69-hdparm.rules`:

```
ACTION=="add", SUBSYSTEM=="block", ENV{ID_SERIAL_SHORT}=="NAAXDNHD", RUN+="/usr/sbin/hdparm -S 241 /dev/%k"
```

## Samba & Time Machine

### Shares

| Share | Path | User | Purpose |
|-------|------|------|---------|
| timemachine | /mnt/hdd/timemachine | backup | macOS Time Machine backups |
| storage | /mnt/hdd/storage | backup | General file storage |

### Configuration

Samba config is in `/etc/samba/smb.conf`:

```ini
[timemachine]
   comment = Time Machine Backup
   path = /mnt/hdd/timemachine
   browseable = yes
   writeable = yes
   create mask = 0600
   directory mask = 0700
   valid users = backup
   fruit:aapl = yes
   fruit:time machine = yes
   vfs objects = catia fruit streams_xattr

[storage]
   comment = General Storage
   path = /mnt/hdd/storage
   browseable = yes
   writeable = yes
   create mask = 0664
   directory mask = 0775
   valid users = backup
```

### Avahi (Bonjour Discovery)

Time Machine auto-discovery is configured in `/etc/avahi/services/timemachine.service`.

### Setup Commands

```bash
# Create backup user
sudo useradd -M -s /usr/sbin/nologin backup
sudo smbpasswd -a backup

# Set ownership
sudo chown -R backup:backup /mnt/hdd/timemachine

# Test config
testparm -s

# Restart services
sudo systemctl restart smbd
sudo systemctl restart avahi-daemon
```

### Mac Setup

1. **System Settings → Time Machine → Add Backup Disk**
2. Select "robertson-walker Time Machine"
3. Login with user: `backup` and your Samba password

## Troubleshooting

### DNS not resolving from external devices

1. Check Pi-hole is running: `sudo docker compose ps pihole`
2. Check listening mode: `sudo docker exec pihole grep listeningMode /etc/pihole/pihole.toml`
3. Should be: `listeningMode = "ALL"`

### Container won't start

1. Check logs: `sudo docker compose logs [service]`
2. Check disk space: `df -h /mnt/ssd/system`
3. Check Docker: `sudo systemctl status docker`

### Paperless can't connect to database

Password mismatch between Paperless and PostgreSQL. Reset with:

```bash
sudo docker exec -it paperless-db psql -U paperless -d paperless -c "ALTER USER paperless WITH PASSWORD 'your-password';"
sudo docker restart paperless
```

## Samba & Time Machine

### Shares

| Share | Path | User | Purpose |
|-------|------|------|---------|
| timemachine | /mnt/hdd/timemachine | backup | macOS Time Machine backups |
| storage | /mnt/hdd/storage | backup | General file storage |

### Configuration Files

- Samba: `/etc/samba/smb.conf`
- Avahi (Time Machine discovery): `/etc/avahi/services/timemachine.service`

### Connecting from Mac

**Time Machine:**
1. System Settings → Time Machine → Add Backup Disk
2. Select "robertson-walker Time Machine"
3. Login: `backup` / (password in password manager)

**Storage:**
1. Finder → Go → Connect to Server
2. `smb://192.168.178.111/storage`
3. Login: `backup` / (password in password manager)

### Managing Samba

```bash
# Test config
testparm -s

# Restart Samba
sudo systemctl restart smbd

# Change password
sudo smbpasswd backup
```

## Recovery from Scratch

1. Flash fresh Ubuntu Server to SD card
2. Clone this repo: `git clone [repo-url] ~/homelab`
3. Copy `.env` from password manager
4. Mount disks (fstab entries above)
5. `cd ~/homelab && sudo docker compose up -d`
6. Restore Docker volumes from backup if needed
7. Reconfigure Samba (see smb.conf additions above)
8. Reconfigure Avahi for Time Machine discovery
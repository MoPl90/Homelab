# Homelab

Raspberry Pi 4 home server configuration.

## Services

| Service | Port | Local URL |
|---------|------|-----------|
| Pi-hole | 80 | pihole.robertson-walker.me |
| Nginx Proxy Manager | 81 | npm.robertson-walker.me |
| Paperless-ngx | 8010 | paperless.robertson-walker.me |
| Portainer | 9000 | portainer.robertson-walker.me |
| Watchtower | - | (no UI) |

## Architecture

Local domain routing works in two steps:

1. **Pi-hole DNS** resolves domain to IP
   - `*.robertson-walker.me` → `192.168.178.111`

2. **Nginx Proxy Manager** routes by subdomain to correct port
   - `paperless.robertson-walker.me` → `localhost:8010`
   - `portainer.robertson-walker.me` → `localhost:9000`
   - etc.

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
NPM: sees "paperless" subdomain, proxies to localhost:8010
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | All service definitions |
| `.env` | Secrets (not in git) |
| `pihole/custom.list` | Local DNS entries |

## Usage

```bash
docker compose up -d
```

## Disk Layout

| Mount | Device | Purpose |
|-------|--------|---------|
| `/mnt/ssd/system` | SSD 122GB | Docker data, logs |
| `/mnt/ssd/data` | SSD 745GB | Personal data |
| `/mnt/hdd/timemachine` | HDD 1.6TB | macOS backups |
| `/mnt/hdd/storage` | HDD 2TB | Paperless inbox, backups |

## Failsafe Design

- All mounts use `nofail` in fstab — system boots even if disks fail
- Logs write to SSD, not SD card (prevents SD wear)
- Docker data on SSD with bind mount from `/var/lib/docker`
- Configs in `~/homelab/` are git-tracked for easy recovery

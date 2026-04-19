#!/bin/bash
# Weekly backup of Docker volumes to HDD

BACKUP_DIR="/mnt/hdd/storage/backups"
DATE=$(date +%Y%m%d)
LOG="/var/log/docker-backup.log"

echo "$(date): Starting Docker volume backup" >> $LOG

# Create backup directory
mkdir -p "$BACKUP_DIR/docker-volumes-$DATE"

# Backup volumes (without stopping containers - using live copy)
rsync -av /var/lib/docker/volumes/ "$BACKUP_DIR/docker-volumes-$DATE/" >> $LOG 2>&1

# Keep only last 4 backups (4 weeks)
cd "$BACKUP_DIR"
ls -dt docker-volumes-* | tail -n +5 | xargs rm -rf 2>/dev/null

echo "$(date): Backup complete" >> $LOG

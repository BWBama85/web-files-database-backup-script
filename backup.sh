#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3 RETURN
exec 1>>$LOG_FILE 2>&1

# Set up variables
. config.inc

log() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - $1"
}

# Create the backup directory if it doesn't already exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
fi

if [ $DEBUG == "y" ]; then
    VERBOSE="v"
fi

# Create a timestamp for the backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create a tar.gz archive for each subdirectory in the data directory, excluding logs
for dir in $(find "$DATA_DIR" -maxdepth 1 -type d); do
    if [ "$dir" != "$DATA_DIR" ]; then
        log "Creating backup for $dir"
        cd "$dir"
        tar zcf "$BACKUP_DIR/${dir##*/}-$TIMESTAMP.tar.gz" --exclude-from="$EXCLUDE_FILES" *
        if [ $? -ne 0 ]; then
            # There was an error creating the backup
            log "Error creating backup for $dir"
            exit 1
        else
            log "Backup for $dir created successfully"
        fi
        cd - >/dev/null 2>&1
    fi
done

# Use mysqldump to backup each MySQL database
for db in $(mysql -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys|test)"); do
    log "Creating MySQL backup for $db"
    mysqldump $MYSQLDUMP_OPTIONS "$db" | gzip >"$BACKUP_DIR/$db-$TIMESTAMP.sql.gz"
    if [ $? -ne 0 ]; then
        # There was an error creating the backup
        log "Error creating MySQL backup for $db"
        exit 1
    else
        log "MySQL backup for $db created successfully"
    fi
done

# Rotate the backups, keeping only the last 8 days of backups
log "Rotating backups, keeping only the last 8 days of backups"
find "$BACKUP_DIR" -mtime +8 -type f -name "*.gz" -delete

# Check to see if we are running out of disk space
total_space=$(df /home/backup-data | awk 'NR==2 {print $2}')
free_space=$(df /home/backup-data | awk 'NR==2 {print $4}')
percent_free=$((free_space * 100 / total_space))

# Check if the percentage of free space is less than 15
if [ $percent_free -lt 15 ]; then
    log "Low disk space on backup server, sending alert"
    if [ -n "$WEBHOOK_URL" ]; then
        curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"Low disk space on backup server. Please free up some space.\"}" $WEBHOOK_URL
    fi
fi

# Send a message with a summary of the backup
BACKUP_SUMMARY=$(find "$BACKUP_DIR" -type f -name "*-$TIMESTAMP*" -exec du -h {} + | awk '{ total += $1 } END { print total }')
MESSAGE=$(echo -n '{"content":"Backup for '$SERVER' completed. \nTotal size of backup: '$BACKUP_SUMMARY'MB"}' | jq -c)
if [ -n "$WEBHOOK_URL" ]; then
    curl -H "Content-Type: application/json" -X POST -d "$MESSAGE" $WEBHOOK_URL
fi

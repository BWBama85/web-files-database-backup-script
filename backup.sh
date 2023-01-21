#!/bin/bash

# Set up variables
BACKUP_DIR="/home/backup-data"
DATA_DIR="/home/nginx/domains"
MYSQLDUMP_OPTIONS="--single-transaction --skip-lock-tables --default-character-set=utf8mb4"
LOG_FILE="/home/backup-data/log.log"
WEBHOOK_URL=""
SERVER=$(uname -n)

# Create the backup directory if it doesn't already exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
fi

# Create a timestamp for the backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create a tar.gz archive for each subdirectory in the data directory, excluding logs
for dir in $(find "$DATA_DIR" -maxdepth 1 -type d); do
    if [ "$dir" != "$DATA_DIR" ]; then
        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Creating backup for $dir..." | tee -a $LOG_FILE
        cd "$dir"
        tar -zcf "$BACKUP_DIR/${dir##*/}-$TIMESTAMP.tar.gz" --exclude=logs *
        if [ $? -ne 0 ]; then
            # There was an error creating the backup
            echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Error creating backup for $dir" | tee -a $LOG_FILE
            exit 1
        else
            echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Backup for $dir created successfully" | tee -a $LOG_FILE
        fi
        cd - >/dev/null 2>&1
    fi
done

# Use mysqldump to backup each MySQL database
for db in $(mysql -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema)"); do
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Creating MySQL backup for $db..." | tee -a $LOG_FILE
    mysqldump $MYSQLDUMP_OPTIONS "$db" | gzip >"$BACKUP_DIR/$db-$TIMESTAMP.sql.gz"
    if [ $? -ne 0 ]; then
        # There was an error creating the backup
        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Error creating MySQL backup for $db" | tee -a $LOG_FILE
        exit 1
    else
        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - MySQL backup for $db created successfully" | tee -a $LOG_FILE
    fi
done

# Rotate the backups, keeping only the last 8 days of backups
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Rotating backups, keeping only the last 8 days of backups..." | tee -a $LOG_FILE
find "$BACKUP_DIR" -mtime +8 -type f -delete

# Check to see if we are running out of disk space
total_space=$(df /home/backup-data | awk 'NR==2 {print $2}')
free_space=$(df /home/backup-data | awk 'NR==2 {print $4}')
percent_free=$((free_space * 100 / total_space))

# Check if the percentage of free space is less than 15
if [ $percent_free -lt 15 ]; then
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Low disk space on backup server, sending alert..." | tee -a $LOG_FILE
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

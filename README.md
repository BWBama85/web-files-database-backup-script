# Website Files & Database Backup Script

This is a straightforward backup script for webservers using MySQL or MariaDB. The script can be run manually or with cron. Once the backup is done, it can optionally send you a notification to a discord channel of your choice via webhooks.

## Crontab Example

Using crontab -e you can run the script at any interval you like. An example is below.

**Run twice a day at 12PM and 6PM**

`0 12,18 * * * /bin/bash /home/backup-data/backup.sh > /dev/null 2>&1`

## Notes

- It assumes that you have a /root/.my.cnf file with credentials stored in it.
- It assumes you are using InnoDB tables

{%- from "cassandra/map.jinja" import backup with context -%}
#!/bin/bash

# Script to erase old backups on Cassandra 'server role' node.
# ---------

    BACKUPDIR="{{ backup.backup_dir }}/full"
    KEEP={{ backup.server.full_backups_to_keep }}
    HOURSFULLBACKUPLIFE={{ backup.server.hours_before_full }} # Lifetime of the latest full backup in seconds

    if [ $HOURSFULLBACKUPLIFE -gt 24 ]; then
        FULLBACKUPLIFE=$(( 24 * 60 * 60 ))
    else
        FULLBACKUPLIFE=$(( $HOURSFULLBACKUPLIFE * 60 * 60 ))
    fi

# Cleanup
# ---------
    echo "Cleanup. Keeping only $KEEP full backups"
    AGE=$(($FULLBACKUPLIFE * $KEEP / 60))
    find $BACKUPDIR -maxdepth 1 -type d -mmin +$AGE -execdir echo "removing: "$BACKUPDIR/{} \; -execdir rm -rf $BACKUPDIR/{} \;

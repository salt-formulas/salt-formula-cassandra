{%- from "cassandra/map.jinja" import backup with context %}
#!/bin/sh

# This script is called remotely by Cassandra 'client role' node and returns appropriate backup that client will restore

if [ $# -eq 0 ]; then
    echo "No arguments provided"
    exit 1
fi

# if arg is not an integer
case $1 in
    ''|*[!0-9]*) echo "Argument must be integer"; exit 1 ;;
    *) ;;
esac

BACKUPDIR="{{ backup.backup_dir }}/full/"
FULL=`find $BACKUPDIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head -$1 | tail -1`

echo "$BACKUPDIR/$FULL/"

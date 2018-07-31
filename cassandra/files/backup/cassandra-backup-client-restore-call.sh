{%- from "cassandra/map.jinja" import backup with context -%}
#!/bin/bash

# Script is to locally prepare appropriate backup to restore from local or remote location and call client-restore script in for loop with every keyspace

# Configuration
# -------------
    PROGNAME="getSnapshot"
    PROGVER="1.0.1"
    ASFCFG="/etc/cassandra"
    DSECFG="/etc/dse/cassandra"
    BACKUPDIR="{{ backup.backup_dir }}/full"
    TMPDIR="$( pwd )/${PROGNAME}.tmp${RANDOM}"
    CLITMPFILE="${TMPDIR}/cqlschema"
    CASIP="127.0.0.1"
    JMXIP="127.0.0.1"
    HOSTNAME="$( hostname )"
    SNAPCREATE=false
    KEYSPFILE="cassandra.keyspace"
    SNAPSFILE="cassandra.snapshot"
    HOSTSFILE="cassandra.hostname"
    DATESFILE="cassandra.snapdate"
    APPENDTIMESTAMP="yes"
    SCRIPTDIR="/usr/local/bin"
    DBALREADYRESTORED="{{ backup.backup_dir }}/dbrestored"
    LOGDIR="/var/log/backups"
    LOGFILE="/var/log/backups/cassandra-restore.log"
    SCPLOG="/var/log/backups/cassandra-restore-scp.log"


if [ -e $DBALREADYRESTORED ]; then
  error "Databases already restored. If you want to restore again delete $DBALREADYRESTORED file and run the script again."
fi

# Create backup directory.
if [ ! -d "$LOGDIR" ] && [ ! -e "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
fi

{%- if backup.client.restore_from == 'remote' %}

echo "Adding ssh-key of remote host to known_hosts"
ssh-keygen -R {{ backup.client.target.host }} 2>&1 | > $SCPLOG
ssh-keyscan {{ backup.client.target.host }} >> ~/.ssh/known_hosts  2>&1 | >> $SCPLOG
REMOTEBACKUPPATH=`ssh cassandra@{{ backup.client.target.host }} "/usr/local/bin/cassandra-restore-call.sh {{ backup.client.restore_latest }}"`

#get files from remote and change variables to local restore dir

LOCALRESTOREDIR=/var/backups/restoreCassandra
FULLBACKUPDIR=$LOCALRESTOREDIR/full

mkdir -p $LOCALRESTOREDIR
rm -rf $LOCALRESTOREDIR/*

echo "SCP getting full backup files"
FULL=`basename $REMOTEBACKUPPATH`
mkdir -p $FULLBACKUPDIR
`scp -rp cassandra@{{ backup.client.target.host }}:$REMOTEBACKUPPATH $FULLBACKUPDIR/$FULL/  >> $SCPLOG 2>&1`

# Check if the scp succeeded or failed
if ! grep -q "No such file or directory" $SCPLOG; then
        echo "SCP from remote host completed OK"
else
        echo "SCP from remote host FAILED"
        exit 1
fi

echo "Restoring db from $FULLBACKUPDIR/$FULL/"
{%- if backup.client.containers is defined %}
{%- for container_name in backup.client.containers %}

docker exec {{ container_name }} mkdir -p $FULLBACKUPDIR/$FULL/
docker cp $SCRIPTDIR/cassandra-backup-restore.sh {{ container_name }}:/

for filename in $FULLBACKUPDIR/$FULL/*; do docker cp $filename {{ container_name }}:$filename; docker exec {{ container_name }} /cassandra-backup-restore.sh -f $filename; docker exec {{ container_name }} rm -rf $filename; done

{%- endfor %}

{%- else %}

for filename in $FULLBACKUPDIR/$FULL/*; do $SCRIPTDIR/cassandra-backup-restore.sh -f $filename; done

{%- endif %}

{%- else %}

FULL=`find $BACKUPDIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head -{{ backup.client.restore_latest }} | tail -1`
echo "Restoring db from $BACKUPDIR/$FULL/"

{%- if backup.client.containers is defined %}
{%- for container_name in backup.client.containers %}

docker exec {{ container_name }} mkdir -p $BACKUPDIR/$FULL/
docker cp $SCRIPTDIR/cassandra-backup-restore.sh {{ container_name }}:/

for filename in $BACKUPDIR/$FULL/*; do docker cp $filename {{ container_name }}:$filename; docker exec {{ container_name }} /cassandra-backup-restore.sh -f $filename; docker exec {{ container_name }} rm -rf $filename; done

{%- endfor %}

{%- else %}

for filename in $BACKUPDIR/$FULL/*; do $SCRIPTDIR/cassandra-backup-restore.sh -f $filename; done

{%- endif %}

{%- endif %}

{%- if backup.client.containers is defined %}
{%- for container_name in backup.client.containers %}

docker exec {{ container_name }} nodetool repair
RC=$?
if [ $RC -eq 0 ]; then
    touch $DBALREADYRESTORED
fi

{%- endfor %}

{%- else %}

nodetool repair
RC=$?
if [ $RC -eq 0 ]; then
    touch $DBALREADYRESTORED
fi

{%- endif %}



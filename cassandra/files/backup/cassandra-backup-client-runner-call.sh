{%- from "cassandra/map.jinja" import backup with context %}
#!/bin/bash
# Script to call cassandra-backup-runner.sh in for loop to backup all keyspaces.
# This script is also able to rsync backed up data to remote host and perform clean up on historical backups

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
    KEEP={{ backup.client.full_backups_to_keep }}
    HOURSFULLBACKUPLIFE={{ backup.client.hours_before_full }} # Lifetime of the latest full backup in seconds
    RSYNCLOG=/var/log/backups/cassandra-rsync.log


    if [ $HOURSFULLBACKUPLIFE -gt 24 ]; then
        FULLBACKUPLIFE=$(( 24 * 60 * 60 ))
    else
        FULLBACKUPLIFE=$(( $HOURSFULLBACKUPLIFE * 60 * 60 ))
    fi

# Functions
# ---------
    function check_dependencies() {
        # Function to iterate through a list of required executables to ensure
        # they are installed and executable by the current user.
        DEPS="awk basename cp cqlsh date dirname echo find "
        DEPS+="getopt grep hostname mkdir rm sed tail tar "
        for bin in $DEPS; do
            $( which $bin >/dev/null 2>&1 ) || NOTFOUND+="$bin "
        done

        if [ ! -z "$NOTFOUND" ]; then
            printf "Error finding required executables: ${NOTFOUND}\n" >&2
            exit 1
        fi
    }


    # Need write access to local directory to create dump file
    if [ ! -w $( pwd ) ]; then
        printf "You must have write access to the current directory $( pwd )\n"
        exit 1
    fi

    if [ ! -d "$RSYNCLOG" ] && [ ! -e "$RSYNCLOG" ]; then
        mkdir -p "$RSYNCLOG"
    fi

    # Get local Cassandra listen address.  Should be loaded via the selected
    # cassandra.yaml file above.
    if [ -z $listen_address ]; then
        CASIP=$( hostname )
    elif [ "$listen_address" == "0.0.0.0" ]; then
        CASIP=127.0.0.1
    else
        CASIP=$listen_address
    fi

    TIMESTAMP=$( date +"%Y%m%d%H%M%S" )
    DATESTRING=$( date )

    cqlsh $CASIP -e "DESC KEYSPACES" |perl -pe 's/\e([^\[\]]|\[.*?[a-zA-Z]|\].*?\a)//g' | sed '/^$/d' > Keyspace_name_schema.cql
    sed 's/\"//g' Keyspace_name_schema.cql  > KEYSPACES_LIST
    for i in `cat KEYSPACES_LIST`; do $SCRIPTDIR/cassandra-backup-runner.sh -k $i -t $TIMESTAMP -d $DATESTRING; done

# rsync just the new or modified backup files
# ---------

    {%- if backup.client.target is defined %}
    echo "Adding ssh-key of remote host to known_hosts"
    ssh-keygen -R {{ backup.client.target.host }} 2>&1 | > $RSYNCLOG
    ssh-keyscan {{ backup.client.target.host }} >> ~/.ssh/known_hosts  2>&1 | >> $RSYNCLOG
    echo "Rsyncing files to remote host"
    /usr/bin/rsync -rhtPv --rsync-path=rsync --progress $BACKUPDIR/* -e ssh cassandra@{{ backup.client.target.host }}:$BACKUPDIR >> $RSYNCLOG

    # Check if the rsync succeeded or failed
    if [ -s $RSYNCLOG ] && ! grep -q "rsync error: " $RSYNCLOG; then
            echo "Rsync to remote host completed OK"
    else
            echo "Rsync to remote host FAILED"
            exit 1
    fi
    {%- endif %}

# Cleanup
# ---------
    echo "Cleanup. Keeping only $KEEP full backups"
    AGE=$(($FULLBACKUPLIFE * $KEEP / 60))
    find $BACKUPDIR -maxdepth 1 -type d -mmin +$AGE -execdir echo "removing: "$BACKUPDIR/{} \; -execdir rm -rf $BACKUPDIR/{} \;


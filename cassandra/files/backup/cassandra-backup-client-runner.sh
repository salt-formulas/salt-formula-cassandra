{%- from "cassandra/map.jinja" import backup with context -%}
#!/bin/bash
# Script to backup Cassandra schema and create snapshot of keyspaces

# Configuration
# -------------
    PROGNAME="getSnapshot"
    PROGVER="1.0.1"
    ASFCFG="/etc/cassandra"
    CASCFG='/etc/cassandra/cassandra.yaml'
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

    function parse_yaml() {
        # Basic (as in imperfect) parsing of a given YAML file.  Parameters
        # are stored as environment variables.
        local prefix=$2
        local s
        local w
        local fs
        s='[[:space:]]*'
        w='[a-zA-Z0-9_]*'
        fs="$(echo @|tr @ '\034')"
        sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
        awk -F"$fs" '{
          indent = length($1)/2;
          if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
          vname[indent] = $2;
          for (i in vname) {if (i > indent) {delete vname[i]}}
          if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
          }
        }' | sed 's/_=/+=/g'
    }

    function usage() {
        printf "Usage: $0 -h\n"
        printf "       $0 -k <keyspace name> [-s <snapshot name>] [-y <cassandra.yaml file>] [--no-timestamp]\n"
        printf "    -h,--help                          Print usage and exit\n"
        printf "    -v,--version                       Print version information and exit\n"
        printf "    -k,--keyspace <keyspace name>      REQUIRED: The name of the keyspace to snapshot\n"
        printf "    -s,--snapshot <snapshot name>      The name of an existing snapshot to package\n"
        printf "    -y,--yaml <cassandra.yaml file>    Alternate cassandra.yaml file\n"
        printf "    -t,--timestamp                     timestamp\n"
        printf "    -d,--datestring                    datestring\n"
        printf "    --no-timestamp                     Don't include a timestamp in the resulting filename\n"
        exit 0
    }

    function version() {
        printf "$PROGNAME version $PROGVER\n"
        printf "Cassandra snapshot packaging utility\n\n"
        printf "Copyright 2016 Applied Infrastructure, LLC\n\n"
        printf "Licensed under the Apache License, Version 2.0 (the \"License\");\n"
        printf "you may not use this file except in compliance with the License.\n"
        printf "You may obtain a copy of the License at\n\n"
        printf "    http://www.apache.org/licenses/LICENSE-2.0\n\n"
        printf "Unless required by applicable law or agreed to in writing, software\n"
        printf "distributed under the License is distributed on an \"AS IS\" BASIS,\n"
        printf "WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n"
        printf "See the License for the specific language governing permissions and\n"
        printf "limitations under the License.\n"
        exit 0
    }

# Validate Input/Environment
# --------------------------
    # Great sample getopt implementation by Cosimo Streppone
    # https://gist.github.com/cosimo/3760587#file-parse-options-sh
    SHORT='hvk:s:y:t:d:'
    LONG='help,version,keyspace:,snapshot:,yaml:,timestamp:,datestring:,no-timestamp'
    OPTS=$( getopt -o $SHORT --long $LONG -n "$0" -- "$@" )

    if [ $? -gt 0 ]; then
        # Exit early if argument parsing failed
        printf "Error parsing command arguments\n" >&2
        exit 1
    fi

    eval set -- "$OPTS"
    while true; do
        case "$1" in
            -h|--help) usage;;
            -v|--version) version;;
            -k|--keyspace) KEYSPACE="$2"; shift 2;;
            -s|--snapshot) SNAPSHOT="$2"; shift 2;;
            -y|--yaml) INPYAML="$2"; shift 2;;
            -t|--timestamp) TIMESTAMP="$2"; shift 2;;
            -d|--datestring) DATESTRING="$2"; shift 2;;
            --no-timestamp) APPENDTIMESTAMP="no"; shift;;
            --) shift; break;;
            *) printf "Error processing command arguments\n" >&2; exit 1;;
        esac
    done

    # Verify required binaries at this point
    check_dependencies

    # Only KEYSPACE is absolutely required
    if [ "$KEYSPACE" == "" ]; then
        printf "You must provide a keyspace name\n"
        exit 1
    fi

    # Need write access to local directory to create dump file
    if [ ! -w $( pwd ) ]; then
        printf "You must have write access to the current directory $( pwd )\n"
        exit 1
    fi

    # Attempt to locate data directory and keyspace files
    YAMLLIST="${INPYAML:-$( find "$DSECFG" "$ASFCFG" -type f -name cassandra.yaml 2>/dev/null ) }"

    for yaml in $YAMLLIST; do
        if [ -r "$yaml" ]; then
            eval $( parse_yaml "$yaml" )
            # Search each data directory in the YAML
            for directory in ${data_file_directories_[@]}; do
                if [ -d "$directory/$KEYSPACE" ]; then
                    # Use the YAML that references the keyspace
                    DATADIR="$directory"
                    YAMLFILE="$yaml"
                    break
                fi
                # Used only when the keyspace can't be found
                TESTED="$TESTED $directory"
            done
        fi
    done

    if [ -z "$TESTED" ] && [ -z "$DATADIR" ]; then
        printf "No data directories, or no cassandra.yaml file found\n" >&2
        exit 1
    elif [ -z "$DATADIR" ] || [ -z "$YAMLFILE" ]; then
        printf "Keyspace data directory could not be found in:\n"
        for dir in $TESTED; do
            printf "    $dir/$KEYSPACE\n"
        done
        exit 1
    fi

# Preparation
# -----------
    eval $( parse_yaml "$YAMLFILE" )

    # Create temporary working directory.  Yes, deliberately avoiding mktemp
    if [ ! -d "$TMPDIR" ] && [ ! -e "$TMPDIR" ]; then
        mkdir -p "$TMPDIR"
    else
        printf "Error creating temporary directory $TMPDIR"
        exit 1
    fi

    # Create backup directory.
    if [ ! -d "$BACKUPDIR" ] && [ ! -e "$BACKUPDIR" ]; then
        mkdir -p "$BACKUPDIR"
    fi

    # Write temp command file for Cassandra CLI
    printf "desc keyspace $KEYSPACE;\n" > $CLITMPFILE

    listen_address=$(/usr/local/bin/cas_get_listen_addr < $CASCFG)
    # Get local Cassandra listen address.  Should be loaded via the selected
    # cassandra.yaml file above.
    if [ -z $listen_address ]; then
        CASIP=$( hostname )
    elif [ "$listen_address" == "0.0.0.0" ]; then
        CASIP=127.0.0.1
    else
        CASIP=$listen_address
    fi

    # Get local Cassandra JMX address
    # Cheating for now - this is *usually* right, but may be set to a real IP
    # in cassandra-env.sh in some environments.
    JMXIP=127.0.0.1

# Create/Pull Snapshot
# --------------------
    if [ -z "$SNAPSHOT" ]; then
        # Create a new snapshot if a snapshot name was not provided
        printf "Creating new snapshot $KEYSPACE\n"

        OUTPUT=$( nodetool -h $JMXIP snapshot $KEYSPACE 2>&1 )
        SNAPSHOT=$( grep -Eo '[0-9]{10}[0-9]+' <<< "$OUTPUT" | tail -1 )

        # Check if the snapshot process failed
        if [ -z "$SNAPSHOT" ]; then
            printf "Problem creating snapshot for keyspace $KEYSPACE\n\n"
            printf "$OUTPUT\n"
            [ "$TMPDIR" != "/" ] && rm -rf "$TMPDIR"
            exit 1
        fi
    else
        # If a snapshot name was provided, check if it exists
        SEARCH=$( find "${DATADIR}/${KEYSPACE}" -type d -name "${SNAPSHOT}" )

        if [ -z "$SEARCH" ]; then
            printf "No snapshots found with name ${SNAPSHOT}\n"
            [ "$TMPDIR" != "/" ] && rm -rf "$TMPDIR"
            exit 1
        else
            printf "Using provided snapshot name ${SNAPSHOT}\n"
        fi
    fi

    # Pull new/existing snapshot
    SNAPDIR="snapshots/$SNAPSHOT"
    SCHEMA="schema-$KEYSPACE-$TIMESTAMP.cdl"

    for dir in $( find "$DATADIR" -regex ".*/$SNAPDIR/[^\.]*.db" ); do
        NEWDIR=$( sed "s|${DATADIR}||" <<< $( dirname $dir ) | \
                  awk -F / '{print "/"$2"/"$3}' )

        mkdir -p "$TMPDIR/$NEWDIR"
        cp $dir "$TMPDIR/$NEWDIR/"
    done

# Backup the schema and create tar archive
# ----------------------------------------
    printf "$KEYSPACE" > "$TMPDIR/$KEYSPFILE"
    printf "$SNAPSHOT" > "$TMPDIR/$SNAPSFILE"
    printf "$HOSTNAME" > "$TMPDIR/$HOSTSFILE"
    printf "$DATESTRING" > "$TMPDIR/$DATESFILE"
    cqlsh $CASIP -k $KEYSPACE -f $CLITMPFILE | tail -n +2 > "$TMPDIR/$SCHEMA"
    RC=$?

    mkdir -p "$BACKUPDIR/$TIMESTAMP"

    if [ $? -gt 0 ] && [ ! -s "$TMPDIR/$SCHEMA" ]; then
        printf "Schema backup failed\n"
        [ "$TMPDIR" != "/" ] && rm -rf "$TMPDIR"
        exit 1
    else
        # Include the timestamp in the filename or not (i.e. --no-timestamp)
        [ "$APPENDTIMESTAMP" == "no" ] && FILENAME="$BACKUPDIR/$TIMESTAMP/$KEYSPACE.tar.gz" \
                                       || FILENAME="$BACKUPDIR/$TIMESTAMP/$KEYSPACE-$TIMESTAMP.tar.gz"

        tar --directory "$TMPDIR" \
            -zcvf $FILENAME \
                  $KEYSPACE \
                  $SCHEMA \
                  $KEYSPFILE \
                  $SNAPSFILE \
                  $HOSTSFILE \
                  $DATESFILE >/dev/null 2>&1
        RC=$?

        if [ $RC -gt 0 ]; then
            printf "Error generating tar archive. Because keyspace $KEYSPACE probably due to not containing any .db files.\n"
            [ "$TMPDIR" != "/" ] && rm -rf "$TMPDIR"
            exit 1
        else
            printf "Successfully created snapshot package $KEYSPACE\n"
            [ "$TMPDIR" != "/" ] && rm -rf "$TMPDIR"
            exit 0
        fi
    fi

# Fin.

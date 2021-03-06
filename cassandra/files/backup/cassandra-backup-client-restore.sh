#!/bin/bash
# Script to restore Cassandra schema and keyspaces from snapshot one by one

# Configuration
# -------------
    PROGNAME="putSnapshot"
    PROGVER="1.0.1"
    ASFCFG="/etc/cassandra"
    DSECFG="/etc/dse/cassandra"
    TEMPDIR="$( pwd )/${PROGNAME}.tmp${RANDOM}"
    CLITMPFILE="${TEMPDIR}/cqlkeyspace"
    KEYSPFILE="cassandra.keyspace"
    SNAPSFILE="cassandra.snapshot"
    HOSTSFILE="cassandra.hostname"
    DATESFILE="cassandra.snapdate"

# Functions
# ---------
    function check_dependencies() {
        # Function to iterate through a list of required executables to ensure
        # they are installed and executable by the current user.
        DEPS="awk cat cqlsh cut echo find getopt grep hostname "
        DEPS+="mkdir rm sed sstableloader tar tr "
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
        printf "       $0 -f <snapshot file> [-n <node address>] [-k <new ks name>] [-d <new dc name>] [-r <new rf>] [-y <cassandra.yaml file>]\n"
        printf "    -h,--help                          Print usage and exit\n"
        printf "    -v,--version                       Print version information and exit\n"
        printf "    -f,--file <snapshot file>          REQUIRED: The snapshot file name (created using the\n"
        printf "                                       getSnapshot utility\n"
        printf "    -n,--node <node address>           Destination Cassandra node IP (defaults to the local\n"
        printf "                                       Cassandra IP if run on a Cassandra node, otherwise\n"
        printf "                                       required in order to connect to Cassandra.  Will take\n"
        printf "                                       precedence if provided and run on a Cassandra node\n"
        printf "    -k,--keyspace <new ks name>        Override the destination keyspace name (defaults to\n"
        printf "                                       the source keyspace name)\n"
        printf "    -d,--datacenter <new dc name>      Override the destination datacenter name (defaults\n"
        printf "                                       to the sourcen datacenter name)\n"
        printf "    -r,--replication <new rf>          Override the destination replication factor (defaults\n"
        printf "                                       to source replication factor)\n"
        printf "    -y,--yaml <cassandra.yaml file>    Alternate cassandra.yaml file\n"
        exit 0
    }

    function version() {
        printf "$PROGNAME version $PROGVER\n"
        printf "Cassandra snapshot loader utility\n\n"
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
    SHORT='hvd:f:n:k:r:y:'
    LONG='help,version,datacenter:,file:,node:,keyspace:,replication:,yaml:'
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
            -f|--file) SNAPPKG="$2"; shift 2;;
            -n|--node) IPINPUT="$2"; shift 2;;
            -k|--keyspace) INPKEYSPACE="$2"; shift 2;;
            -d|--datacenter) DATACENTER="$2"; shift 2;;
            -r|--replication) RFACTOR="$2"; shift 2;;
            -y|--yaml) INPYAML="$2"; shift 2;;
            --) shift; break;;
            *) printf "Error processing command arguments\n" >&2; exit 1;;
        esac
    done

    # Verify required binaries at this point
    check_dependencies

    # Only a snapshot file is required
    if [ ! -r "$SNAPPKG" ]; then
        printf "You must provide the location of a snapshot package\n"
        exit 1
    fi

    # Need write access to local directory to create dump file
    if [ ! -w $( pwd ) ]; then
        printf "You must have write access to the current directory $( pwd )\n"
        exit 1
    fi

    # Attempt to locate a local Cassandra install and YAML file
    YAMLLIST="${INPYAML:-$( find "$DSECFG" "$ASFCFG" -type f -name cassandra.yaml 2>/dev/null ) }"

    for yaml in $YAMLLIST; do
        if [ -r "$yaml" ]; then
            # Cassandra YAML found - load it (assume a local Cassandra)
            eval $( parse_yaml "$yaml" )
            YAMLFILE="$yaml"

            if [ -z $listen_address ]; then
                CASIP=$( hostname )
            elif [ "$listen_address" == "0.0.0.0" ]; then
                CASIP=127.0.0.1
            else
                CASIP=$listen_address
            fi
            break
        fi
    done

    # Determine IP to use to connect to Cassandra.  If an IP is provided via
    # -n,--node argument, prefer it.  If not, and a Cassandra IP cannot be
    # discovered via YAML (i.e. this is not a Cassandra node), then return
    # an error and exit.
    if [ ! -z $IPINPUT ]; then
        CASIP="$IPINPUT"
    elif [ -z $CASIP ]; then
        printf "Cassandra IP not provided and not discoverable locally\n"
        exit 1
    fi

    # Check if a new keyspace name is provided, and validate input
    if [ -z $INPKEYSPACE ]; then
        printf "New keyspace name not provided, using original keyspace name\n"
    elif [[ ! "$INPKEYSPACE" =~ ^[_a-zA-Z0-9]*$ ]]; then
        printf "Cassandra keyspace names can only contain alpha-numerics and underscore (_)\n"
        exit 1
    else
        KEYSPACE="$INPKEYSPACE"
        printf "New keyspace name $KEYSPACE to be used\n"
    fi

    # Let the user know which datacenter and replication factor values being used
    if [ -z $DATACENTER ]; then
        printf "New datacenter name not provided, using original datacenter name\n"
    fi
    if [ -z $RFACTOR ]; then
        printf "New replication factor not provided, using original replication factor\n"
    fi

# Preparation
# -----------
    # Remove local temp directory
    [ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"

    # Verify/Extract Snapshot Package
    tar -tvf "$SNAPPKG" 2>&1 | grep "$KEYSPFILE" 2>&1 >/dev/null
    RC=$?

    if [ $RC -gt 0 ]; then
        printf "\nSnapshot package $SNAPPKG appears invalid or corrupt\n"
        exit 1
    else
        # Create temporary working directory.  Yes, deliberately avoiding mktemp
        if [ ! -d "$TEMPDIR" ] && [ ! -e "$TEMPDIR" ]; then
            mkdir -p "$TEMPDIR"
        else
            printf "\nError creating temporary directory $TEMPDIR"
            exit 1
        fi

        # Extract snapshot package
        tar -xf "$SNAPPKG" --directory "$TEMPDIR"
    fi

# Prepare Snapshot
# ----------------
    FILEKSNAME=$( cat "${TEMPDIR}/${KEYSPFILE}" )
    FILEHOSTNAME=$( cat "${TEMPDIR}/${HOSTSFILE}" )
    FILESNAPDATE=$( cat "${TEMPDIR}/${DATESFILE}" )
    SCHEMAFILE=$( ls "${TEMPDIR}"/schema-${FILEKSNAME}-*.cdl 2>/dev/null )

    # Place schema on single line and extract replication setup
    FILEREPL=$( sed ':a;N;$!ba;s/\n/ /g' "$SCHEMAFILE" | \
                grep -Eo 'replication ?= ?{[^}]*}' | \
                tr -dc "[:alnum:],:=" | \
                cut -d, -f 2 )
    FILEDCNAME=$( cut -d: -f 1 <<< ${FILEREPL} )
    FILERFACTOR=$( cut -d: -f 2 <<< ${FILEREPL} )

    if [ ! -z $KEYSPACE ]; then
        # Update keyspace names in snapshot
        sed -i 's/'$FILEKSNAME'/'$KEYSPACE'/g' "$SCHEMAFILE"
        mv "${TEMPDIR}/${FILEKSNAME}" "${TEMPDIR}/${KEYSPACE}"
        for dbfile in $( find "${TEMPDIR}/${KEYSPACE}" -type f ); do
            if grep "${FILEKSNAME}" <<< "${dbfile}" >/dev/null; then
                mv "$dbfile" "${dbfile//$FILEKSNAME/$KEYSPACE}"
            fi
        done
        NEWKSNAME=$KEYSPACE
    else
        NEWKSNAME=$FILEKSNAME
    fi

    if [ ! -z $DATACENTER ]; then
        # Update datacenter name in snapshot
        sed -i 's/'$FILEDCNAME'/'$DATACENTER'/g' "$SCHEMAFILE"
        DCNAME=$DATACENTER
    else
        DCNAME=$FILEDCNAME
    fi

    if [ ! -z $RFACTOR ]; then
        # Update replication factor in snapshot
        sed -i 's/\(\d039'$DCNAME'\d039[^:]*:[^\d039]*\d039\)'$FILERFACTOR'\(\d039\)/\1'$RFACTOR'\2/' "$SCHEMAFILE"
        NEWRFACTOR="$RFACTOR"
    else
        NEWRFACTOR="$FILERFACTOR"
    fi

# Load Snapshot
# -------------
    # Check for keyspace name conflict
    while true; do
        echo "describe keyspace $NEWKSNAME;" > "$CLITMPFILE"

        # Use CQL version in environment, if available
        [ -z $CQLVER ] && CQLSHVER="" || CQLSHVER="--cqlversion=$CQLVER"
        OUTPUT=$( cqlsh -f $CLITMPFILE $CQLSHVER $CASIP 2>&1 )
        RC=$?

        if [ $RC -eq 0 ] && grep -qi 'CREATE KEYSPACE '$NEWKSNAME' ' <<< $OUTPUT; then
            printf "ERROR: Keyspace name $NEWKSNAME conflicts with existing keyspace name\n"
            [ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"
            exit 1
        elif grep -qi 'version .\?[.0-9]*.\? is not' <<< $OUTPUT; then
            ERRORCQLVER=$( grep -o 'version .\?[0-9.]*.\? is not' <<< $OUTPUT | tr -dc ' 0-9.' )
            SUPPORTED=($( grep -Eo 'upported( versions)?: .*[ 0-9.,]*' <<< $OUTPUT | tr -dc ' 0-9.' ))
{% raw %}
            CQLVER=${SUPPORTED[$((${#SUPPORTED[@]}-1))]}
{% endraw %}
            printf "Default CQL version $ERRORCQLVER not supported by Cassandra at ${CASIP}.\n"
            printf "Reported versions are ${SUPPORTED[@]}.  Attempting with ${CQLVER}.\n"
            continue
        elif grep -qi 'connection error\|not connect' <<< $OUTPUT; then
            printf "ERROR: Unable to connect to Cassandra at ${CASIP}.\n"
            [ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"
            exit 1
        elif [ $RC -eq 1 ]; then
            printf "ERROR: Error executing cqlsh command:\n ${OUTPUT}\n"
            [ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"
            exit 1
        else
            printf "Performing Import:\n"
            printf "    Original cassandra host: $FILEHOSTNAME\n"
            printf "    Original keyspace name: $FILEKSNAME\n"
            printf "    Original snapshot date: $FILESNAPDATE\n\n"
            printf "    Importing schema into keyspace $NEWKSNAME\n"
            printf "       Using datacenter $DCNAME and replication factor $NEWRFACTOR\n"

            # Wait - give the user a chance to panic and CTRL-C out
            sleep 5

            # Create schema for the new keyspace
            cqlsh -f "$SCHEMAFILE" $CQLSHVER $CASIP

            printf "    Loading snapshot into keyspace $NEWKSNAME\n"
            for columnfamily in `ls "${TEMPDIR}/${NEWKSNAME}"`; do
                sstableloader -d $CASIP "${TEMPDIR}/${NEWKSNAME}/${columnfamily}"
            done

            printf "\n\nImport operation complete - check output for errors\n"
            [ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"
            exit 0
        fi
    done

# Fin.

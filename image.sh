#!/bin/bash

##
#   DRIVER SCRIPT
##

## Functions
err() { cat <<< "$@" 1>&2 ; }

## Sanity check

SD_ABS_NAME="/usr/share/imagesh/scripts"
SD_REL_NAME="scripts"

if [ ! -d ./$SD_REL_NAME ] ; then
    if [ ! -d $SD_ABS_NAME ] ; then
        err "Missing scripts directory" 
        exit 1
    else
        SD=$SD_ABS_NAME
    fi
else
    SD=$(pwd)/$SD_REL_NAME
fi

[ -f $SD/sanity-check.sh ] && $SD/sanity-check.sh $SD || { err "Sanity check failed" ; exit 1 ; }

## Process arguments

VERBOSE=1
CONFIG_FILES=
HELP=
REMOTE=
REMOTEDIR=
BATCH=
RETRIEVE=

while [ "$#" -gt 0 ] ; do
    case $1 in
        --help)
            HELP=1
            shift 1
            ;;
        --quiet)
            VERBOSE=
            shift 1
            ;;
        -q)
            VERBOSE=
            shift 1
            ;;
        --remote)
            REMOTE=$2
            shift 2
            ;;
        --remote-dir)
            REMOTEDIR=$2
            shift 2
            ;;
        --retrieve)
            RETRIEVE=$2
            [ ! "$RETRIEVE" ] && RETRIEVE="."
            shift 2
            ;;
        *)
            CONFIG_FILES="$1 $CONFIG_FILES"
            shift 1
            ;;
    esac
done

## Help

if [ "$HELP" ] ; then
    err "Syntax: image.sh [--help] [-q|--quiet] [config_files...]"
    exit 1
fi

## Load configuration(s)

[ "$VERBOSE" ] && echo "Script directory: $SD"

TMPDIR=$(mktemp -d)
trap "{ rm -r $TMPDIR ; exit ; }" EXIT

[ "$VERBOSE" ] && echo "Temporary directory: $TMPDIR"

cp $SD/master_config $TMPDIR/config

for FILE in $CONFIG_FILES ; do
    [ ! -e $FILE ] && { err "Missing configuration file $FILE" ; exit 1 ; }
    [ "$VERBOSE" ] && echo "Loading configuration file $FILE"

    while read KEY VAL ; do
        [ -z "$(grep "$KEY" $TMPDIR/config)" ] && err "Warning: unknown configuration key '$KEY' in $FILE"
        sed -i 's,\('"$KEY"' \).*,\1'"$(sed 's,^~,'$HOME',' <<< $VAL)"',' $TMPDIR/config
    done < $FILE
done

echo "$SD" > $TMPDIR/sd
echo "$VERBOSE" > $TMPDIR/verbose
echo "$HOME" > $TMPDIR/home


## Optional: establish remote connection

#if [ "$REMOTE" ] ; then
#    [ ! "$REMOTEDIR" ] && REMOTEDIR=~/.imagegen
#    [ "$VERBOSE" ] && echo "Synchronizing with remote host folder $REMOTEDIR"
#    scp -r {$SD,$TMPDIR/{config,verbose}} $REMOTE:$REMOTEDIR || { err "Failed to synchronize with remote host" ; exit 1 ; }
#    [ "$VERBOSE" ] && echo "Executing on remote host"
#    ssh $REMOTE "~/.imagegen/scripts/deploy-remote.sh" || exit 1
#    [ "$RETRIEVE" ] && ssh $REMOTE "[ -e $REMOTEDIR/img ]" && { echo "Retrieving remote image" ; rsync $REMOTE:$REMOTEDIR/img $RETRIEVE || exit 1 ; }
#else
#    ## Launch main script
#
    env - $SD/image-main.sh $TMPDIR
#fi



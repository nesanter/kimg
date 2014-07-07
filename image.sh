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

for ARG in "$@" ; do
    case $ARG in
        --help)
            HELP=1
            ;;
        --quiet)
            VERBOSE=
            ;;
        -q)
            VERBOSE=
            ;;
        *)
            CONFIG_FILES="$ARG $CONFIG_FILE"
            ;;
    esac
done

## Load configuration(s)

[ $VERBOSE ] && echo "Script directory: $SD"

TMPDIR=$(mktemp -d)
trap "{ rm -r $TMPDIR ; exit ; }" EXIT

[ $VERBOSE ] && echo "Temporary directory: $TMPDIR"

cp $SD/master_config $TMPDIR/config

for FILE in $CONFIG_FILES ; do
    [ ! -e $FILE ] && { err "Missing configuration file $FILE" ; exit 1 ; }
    [ $VERBOSE ] && echo "Loading configuration file $FILE"

    while read KEY VAL ; do
        [ -z "$(grep "$KEY" $TMPDIR/config)" ] && err "Warning: unknown configuration key '$KEY' in $FILE"
        sed -i 's,\('"$KEY"' \).*,\1'"$VAL"',' $TMPDIR/config
    done < $FILE
done

## Launch main tool

echo "$SD" > $TMPDIR/sd
echo "$VERBOSE" > $TMPDIR/verbose

env - $SD/image-main.sh $TMPDIR

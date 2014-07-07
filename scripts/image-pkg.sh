#!/bin/bash

##
#   IMAGE (BASE) PACKAGE INSTALLER
#   argument 1: tmp directory
#   argument 2: package name
##

# Functions

err() { cat <<< "$@" 1>&2 ; }

# Check handoff

TMPDIR=$1

[ -d "$TMPDIR" ] || { err "Missing handoff directory (PKG)" ; exit 1 ; }

SD=$(cat $TMPDIR/sd)

echo $(pwd)

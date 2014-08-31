#!/bin/bash

##
#   IMAGE (BASE) PACKAGE INSTALLER
#   argument 1: tmp directory
#   argument 2: package name
#   starts in source directory (<img>/sources)
##

TMPDIR=$1
PKG=$2

## Functions

err() { cat <<< "$@" 1>&2 ; }
cfg() { sed -n 's/'"$1"' \(.*\)/\1/p' $TMPDIR/config ; }
vars() {
    sed -n '
    :loop
    /\$<.*\/>/ {
        s/\$<\([^\/]*\)\/>/$<!\1\/!>/
        h
        s/.*\$<!\([^\/]*\)\/!>.*/\1/
        p
        g
        s/\$<!\([^\/]*\)\/!>//
        b loop
    }' | sort | uniq
}
get() {
    sed -n 'H
    /<\/'$1'>/{
        x
        s/.*<'$1'>\(.*\)<\/'$1'>.*/\1/
        t match
        b end
    :match
        s/^\n//
        s/\n$//
        p
    :end
    }'
}

## Check handoff

[ -d "$TMPDIR" ] || { err "Missing handoff directory (PKG)" ; exit 1 ; }

SD=$(cat $TMPDIR/sd)
DL_DIR=$(cat $TMPDIR/dldir)
CORE=$(cfg "core")

PV=$(command -v pv)

## Sanity

[ -e $SD/image-pkgs/$CORE/$PKG/pkg ] || { err "Missing pkg file ($PKG)" ; exit 1 ; }

## Create source sub-directory

ROOTDIR=$(pwd)

PKGDIR=$ROOTDIR/sources/pkg-$PKG

[ -e $PKGDIR ] && { cat <<< "Removing previously existing directory for $PKG" 1>&2 ; rm -r $PKGDIR ; }
mkdir $PKGDIR

## Create log

log() { cat <<< "$@" >> $PKGDIR/log ; }
logp() { log "$@" ; cat <<< "$@" ; }
loge() { cat <<< "$@" >> $PKGDIR/errlog ; }

## Parse pkg file

cp $SD/image-pkgs/$CORE/$PKG/pkg $PKGDIR
PKGFILE=$PKGDIR/pkg

# Resolve variables

PKGVARS=$(vars < $PKGFILE)
for VAR in $PKGVARS ; do
    case $VAR in
        root)
            VAL=$(cat $TMPDIR/root)
            ;;
        arch)
            VAL=$(cfg "arch")
            ;;
        jobs)
            VAL=$(cfg "jobs")
            ;;
        target)
            VAL=$(cfg "arch")-u-linux-gnu
            ;;
        *)
            VAL=$(get $VAR < $PKGFILE)
            ;;
    esac
    sed -i '/\$<'$VAR'\/>/ {s/\$<'$VAR'\/>/'$VAL'/g}' $PKGFILE
done

cat $PKGFILE

# Get values

PKGNAME=$(get pkg < $PKGFILE)
SOURCES=$(get sources < $PKGFILE)
EXTRACT=$(get extract < $PKGFILE)
BUILDDIR=$(get builddir < $PKGFILE)
KEEP=$(get keep < $PKGFILE)
PRE=$(get pre < $PKGFILE)
BUIKD=$(get build < $PKGFILE)

## Download sources

cd $PKGDIR

for SRC in $SOURCES ; do
    logp "Downloading $SRC"
    OBJ=$(sed 's/.*\/\([^\/]*\)/\1/' <<< $SRC)
    if [ "$DL_DIR" ] ; then
        [ ! -e $DL_DIR/$OBJ ] && { wget -P $DL_DIR $SRC 2>&1 || { err "Failed to download source $SRC" ; exit 1 ; } ; }
        cp $DL_DIR/$OBJ .
    else
        wget $SRC 2>&1 || { err "Failed to download source $SRC" ; exit 1 ; }
    fi
done

extract() {
    logp "Extracting $1 ($PV)"
    if [ "$PV" ] ; then
        mkfifo $TMPDIR/pv-pipe
        (cat $TMPDIR/pv-pipe)&
        case $(grep -o '\.[^\.]*$' <<< $1) in
            .tar)
                pv -f $1 2>$TMPDIR/pv-pipe | tar x
                ;;
            .xz)
                pv -f $1 2>$TMPDIR/pv-pipe | tar xJ
                ;;
            .bz2)
                pv -f $1 2>$TMPDIR/pv-pipe | tar xj
                ;;
            .gz)
                pv -f $1 2>$TMPDIR/pv-pipe | tar xz
                ;;
            .lzma)
                pv -f $1 2>$TMPDIR/pv-pipe | tar x --lzma
                ;;
            *)
                logp "Unknown file extension for $1; skipping extraction"
                ;;
        esac

        wait
        rm $TMPDIR/pv-pipe
    else
        tar -xf $1
    fi 
}

case $EXTRACT in
    all)
        SRCFILES=$(ls)
        for FILE in $SRCFILES ; do
            [ "$FILE" == "pkg" -o "$FILE" == "log" -o "$FILE" == "errlog" ] || extract $FILE
        done
        ;;
    none)
        ;;
    *)
        for FILE in $EXTRACT ; do
            [ ! -e $FILE ] && { err "Missing file $FILE; cannot extract" ; exit 1 ; }
            extract $FILE
        done
        ;;
esac

## Run pre-build script

logp "Running pre-build script"

get pre < $PKGFILE > pre.sh
{ bash pre.sh 3>&2 2>&1 1>&3 || exit 1 ; } 2>> $PKGDIR/log | tee -a $PKGDIR/errlog

if [ "$BUILDDIR" == "yes" ] ; then
    mkdir -p build
    cd build
fi

## Run build script

logp "Running build script"

get build < $PKGFILE > build.sh

mkfifo .p
mkfifo .perr

( tee -a $PKGDIR/log < .p | awk 'BEGIN {ORS=""} {print "."} NR%10==0 {fflush()}' )&
( tee -a $PKGDIR/errlog < .perr | awk 'BEGIN {ORS=""} {print "!"; fflush()}' )&

{ bash build.sh || exit 1 ; } > .p 2> .perr

wait

rm .p
rm .perr

## Cleanup

cd $ROOTDIR

[ ! "$KEEP"== "yes" ] && { logp "Cleaning package" ; rm -r $PKGDIR ; }

logp "Package complete"

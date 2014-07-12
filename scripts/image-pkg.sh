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
SRC_DIR_RAW=$(cfg src_dir)
if [ -z "$SRC_DIR_RAW" ] ; then
    SRC_DIR=sources
else
    SRC_DIR=$SRC_DIR_RAW
fi
DL_DIR_RAW=$(cfg dl_dir)
if [ -z "$DL_DIR_RAW" ] ; then
    DL_DIR="."
else
    DL_DIR=$DL_DIR_RAW
    mkdir -p $DL_DIR
fi

PV=$(command -v pv)

## Sanity

[ -e $SD/base/$PKG/pkg ] || { err "Missing pkg file ($PKG)" ; exit 1 ; }

## Create source sub-directory

PKGDIR=$(pwd)/$SRC_DIR/pkg-$PKG
mkdir -p $PKGDIR

## Create log

log() { cat <<< "$@" > $PKGDIR/log ; }
logp() { log "$@" ; cat <<< "$@" ; }
loge() { cat <<< "$@" > $PKGDIR/errlog ; }

## Parse pkg file

cp $SD/base/$PKG/pkg $PKGDIR
PKGFILE=$PKGDIR/pkg

# Resolve variables

PKGVARS=$(vars < $PKGFILE)
for VAR in $PKGVARS ; do
    case $VAR in
        root)
            VAL=$(cat $TMPDIR/root)
            ;;
        arch)
            VAL=$(cfg arch)
            ;;
        *)
            VAL=$(get $VAR < $PKGFILE)
            ;;
    esac
    sed -i '/\$<'$VAR'\/>/ {s/\$<'$VAR'\/>/'$VAL'/g}' $PKGFILE
done

cat $PKGFILE

# Get values

PKGNAME=$($SD/get.sh pkg < $PKGFILE)
SOURCES=$($SD/get.sh sources < $PKGFILE)
EXTRACT=$($SD/get.sh extract < $PKGFILE)
BUILDDIR=$($SD/get.sh builddir <$PKGFILE)

## Download sources

mkdir -p $SRC_DIR/pkg-$PKG
cd $SRC_DIR/pkg-$PKG

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
    if [ "$PV" ] ; then
        case $(grep -o '\.[^\.]$' <<< $1) in
            .tar)
                pv $1 | tar x
                ;;
            .xz)
                pv $1 | tar xJ
                ;;
            .bz2)
                pv $1 | tar xj
                ;;
            .gz)
                pv $1 | tar xz
                ;;
            .lzma)
                pv $1 | tar x --lzma
                ;;
            *)
                logp "Unknown file extension for $1; skipping extraction"
                ;;
        esac
    else
        tar -xf $1
    fi 
}

case $EXTRACT in
    all)
        for FILE in $(ls) ; do
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




#while read ACTION ARGS ; do
#    case $ACTION in
#        dl)
#            OBJ=$(sed 's/.*\/\([^\/]*\)/\1/' <<< $ARGS)
#            if [ "$DL_DIR" ] ; then
#                [ ! -e $DL_DIR/$OBJ ] && { wget -P $DL_DIR $ARGS || { err "Failed to download source $ARGS" ; exit 1 ; } ; }
#                cp $DL_DIR/$PKG .
#            else
#                wget $ARGS || { err "Failed to download source $ARGS" ; exit 1 ; }
#            fi
#            ;;
#        extract)
#            EXT=$(sed 's/.*\.\([^\.]*\)/\1/' <<< $ARGS)
#            case $EXT in
#                tar)
#                    pv $ARGS | tar x
#                    ;;
#                xz)
#                    pv $ARGS | tar xJ
#                    ;;
#                bz2)
#                    pv $ARGS | tar xj
#                    ;;
#                gz)
#                    pv $ARGS | tar xz
#                    ;;
#                lzma)
#                    pv $ARGS | tar x --lzma
#                    ;;
#                *)
#                    err "Unknown file extensions $EXT"
#                    exit 1
#                    ;;
#            esac
#            ;;
#        exec)
#            sh -c "$ARGS" || { err "Failed to execute action ($ARGS)" ; exit 1 ; }
#            ;;
#        sh)
#            [ -e "$SD/base/$PKG/$ARGS" ] || { err "Failed to execute nonexistant scripts ($ARGS) ; exit 1 ; }
#            sh $SD/base/$PKG/$ARGS || { err "Failed to execute action script ($ARGS)" ; exit 1 ; }
#            ;;
#        build)
#
#            sh $ARGS
#
#    esac
#
#done < $SD/base/$PKG/actions

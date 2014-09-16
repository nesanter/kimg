#!/bin/bash

##
#   IMAGE GENERATOR SCRIPT
##

## Functions

err() { cat <<< "$@" >> $ERRLOG ; }
log() { cat <<< "$@" >> $LOG ; }
cfg() { sed -n 's/'"$1"' \(.*\)/\1/p' $TMPDIR/config ; }

cleanup() {
    cd $BASE_DIR
    [ -e "$IMG_NAME" ] && [ "$DONE" == "0" ] && [ "$SAVE" == "0" ] && { log "Removing incomplete image" ; rm $IMG_NAME ; }
    [ -d "$IMG_DIR" ] && { mountpoint -q $IMG_DIR && sudo $(command -v umount) $IMG_DIR ; rmdir $IMG_DIR ; }
    [ -h /tools ] && sudo $(command -v rm) /tools
    log "ENDLOG"
    err "ENDLOG"
    wait
}

## Check for tmp directory (argument 1)

[ -d "$1" ] || { cat <<< "Missing TMPDIR handoff" 1>&2 ; exit 1 ; }

TMPDIR=$1
SD=$(cat $TMPDIR/sd)
VERBOSE=$(cat $TMPDIR/verbose)

LOG=$TMPDIR/log
ERRLOG=$TMPDIR/errlog

## Set up logging

mkfifo $LOG
mkfifo $ERRLOG
SNAP=$(date +%s)
$SD/logger.sh $TMPDIR $(cfg "log_dir") log-$SNAP errlog-$SNAP&

## Begin

PV=$(command -v pv)

TILDE=$(sed 's/\//\\\//g' < $TMPDIR/home)
BASE_DIR=$(cfg "base_dir" | sed 's/^\./'$(pwd | sed 's/\//\\\//g')'/;s/^~/'$TILDE'/')
IMG_NAME=$(cfg "img_name")
IMG_SIZE=$(cfg "img_size")
DL_DIR=$(cfg "dl_dir" | sed 's/^\./'$(pwd | sed 's/\//\\\//g')'/;s/^~/'$TILDE'/')
KBYTES=$(dc <<< "$IMG_SIZE 1024*p")
SAVE=$(cfg "save")
CORE=$(cfg "core")

cat <<< $DL_DIR > $TMPDIR/dldir

DONE=0
trap "{ cleanup ; exit ; }" EXIT

[ -d "$BASE_DIR" ] || { err "Missing base directory" ; exit 1 ; }

cd $BASE_DIR

RESUME=
[ -e "$IMG_NAME" ] && { log "Existing image found; attempting to resume" ; RESUME=1 ; }

[ "$RESUME" ] || {
    [ $(df --output=avail . | tail -n 1) -lt $KBYTES ] && { err "Not enough space on device for image file" ; exit 1 ; }

    log "Creating image file"

    [ "$VERBOSE" ] && [ "$PV" ] && \
        dd if=/dev/zero bs=1M count=$IMG_SIZE status=none | pv -s "$IMG_SIZE"m | dd status=none of=$IMG_NAME || \
        dd if=/dev/zero bs=1M count=$IMG_SIZE of=$IMG_NAME status=none

    [ -e "$IMG_NAME" ] || { err "Error creating image file" ; exit 1 ; }

    log "Making file system"

    mkfs -t $(cfg "fs_type") -q $(cfg "fs_opts") $IMG_NAME >> $LOG 2>> $ERRLOG || { err "Error creating filesystem on image" ; exit 1 ; }
}

IMG_DIR=$(sed 's/[\.].*$//' <<< $IMG_NAME)

cat <<< $IMG_DIR > $TMPDIR/root

mkdir $IMG_DIR || { err "Error creating image directory" ; exit 1 ; }

log "Mounting image (permission required)"

if [ "$MOUNT_OPTS" ] ; then
    sudo $(command -v su) -c "{ mount -o loop,$MOUNT_OPTS $IMG_NAME $IMG_DIR ; chown $(stat -c %u:%g $IMG_NAME) $IMG_DIR ; }" 2>> $ERRLOG || exit 1
else
    sudo $(command -v su) -c "{ mount -o loop $IMG_NAME $IMG_DIR ; chown $(stat -c %u:%g $IMG_NAME) $IMG_DIR ; }" 2>> $ERRLOG || exit 1
fi

cd $IMG_DIR

[ -e .resume ] && log "Resume file found" || {
    mkdir tools

    [ -z "$SRC_DIR" ] && mkdir sources || mkdir -p $SRC_DIR

    touch .resume
}

sudo $(command -v ln) -s $BASE_DIR/$IMG_DIR/tools / 2>> $ERRLOG || exit 1

## Environment

set +h
umask 022

export LC_ALL=POSIX
export PATH=/tools/bin:$PATH

## Install tools

log "Installing core packageset $CORE"

awk '($0 !~ /^#/) {print;}' $SD/image-pkgs/$CORE/manifest | \
    while read PKG ; do
    [ -d "$SD/image-pkgs/$CORE/$PKG" ] || { err "Package $PKG in manifest not in packages" ; exit 1 ; }

    log "Installing package $PKG"

    $SD/image-pkg.sh $TMPDIR $PKG 2>> $ERRLOG || { err "Error installing package $PKG" ; exit 1 ; }
    
    log "Finished package $PKG"
    cat <<< $PKG >> .resume
done || { exit 1 ; }
log "Finished $CORE"


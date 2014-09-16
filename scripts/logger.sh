#!/bin/bash

TMPDIR=$1

[ -e "$TMPDIR" ] || { echo "[LOGGER] Missing TMPDIR handoff" 1>&2 ; exit 1 ; }

VERBOSE=$(cat $TMPDIR/verbose)

LOGPIPE=$TMPDIR/log
ERRLOGPIPE=$TMPDIR/errlog

LOG=$TMPDIR/log-out
ERRLOG=$TMPDIR/errlog-out

cat <<< "IMAGEGEN LOG $(date)" > $LOG
cat <<< "(DEST $2)" > $LOG
cat <<< "IMAGEGEN ERRLOG $(date)" > $ERRLOG
cat <<< "(DEST $3)" > $ERRLOG

(while [ -e $LOGPIPE ] ; do
    MSG=$(cat < $LOGPIPE)
    [ "$MSG" == "ENDLOG" ] && exit
    [ -n "$MSG" ] && { [ $VERBOSE ] && cat <<< "$MSG" | tee -a $LOG || cat <<< "$MSG" > $LOG ; }
done)&

(while [ -e $ERRLOGPIPE ] ; do
    MSG=$(cat < $ERRLOGPIPE)
    [ "$MSG" == "ENDLOG" ] && exit
    [ -n "$MSG" ] && cat <<< "$MSG" | tee -a $ERRLOG
done)&

wait

cp $LOG $2/$3
cp $ERRLOG $2/$4

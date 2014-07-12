#!/bin/bash

../$PKGDIR/configure \
    --prefix=/tools \
    --with-sysroot=$ROOT \
    --target=$TARGET \
    --disable-nls \
    --disable-werror || exit 1

make -j$JOBS || exit 1

case $(uname -m) in
    x86_64) mkdir /tools/lib && ln -s lib /tools/lib64 ;;
esac

make install || exit 1

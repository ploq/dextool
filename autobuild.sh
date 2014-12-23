#!/bin/bash
ROOT=$PWD
INOTIFY_PATH="$ROOT/source $ROOT/dub.json"

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

# sanity check
test ! -e $ROOT/dub.json && echo "Missing dub.json" && exit 1

# create build if missing
# test ! -d build && mkdir build

# trap "build_release" INT

# 0 = failed, 1 = ok
BUILD_PASSED=0

function check_status() {
    RVAL=$?
    MSG=$1
    if [[ $RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
        return 0
    fi
    echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    return 1
}

function builder() {
    BUILD_PASSED=0
    dub build -c unittest -b unittest
    check_status "COMPILE"
    if [[ $? -eq 0 ]]; then
        BUILD_PASSED=1
    fi
}

function builder_release() {
    dub build
    check_status "RELEASE"
}

function watch_tests() {
while :
do
    echo -e "${C_YELLOW}================================${C_NONE}"
    builder
    if [[ $BUILD_PASSED -eq 1 ]]; then
        $ROOT/build/unittest
        check_status "TEST"
        if [[ $? -eq 0 ]]; then
            builder_release
            mplayer /usr/share/sounds/KDE-Sys-App-Positive.ogg 2>/dev/null >/dev/null
        else
            mplayer /usr/share/sounds/KDE-Sys-App-Negative.ogg 2>/dev/null >/dev/null
        fi
    else
        mplayer /usr/share/sounds/KDE-Sys-App-Error.ogg 2>/dev/null >/dev/null
    fi

    IFILES=$(inotifywait -q -r -e MODIFY -e ATTRIB -e CREATE --format %w $INOTIFY_PATH)
    echo "Change detected in: $IFILES"
    sleep 1
done
}

echo "Started watching path: "
echo $INOTIFY_PATH | tr "[:blank:]" "\n"
watch_tests

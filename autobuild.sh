#!/bin/bash
ROOT=$PWD
INOTIFY_PATH="$ROOT/source $ROOT/clang $ROOT/dub.json"

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

# sanity check
test ! -e $ROOT/dub.json && echo "Missing dub.json" && exit 1

# create build if missing
test ! -d build && mkdir build

# trap "build_release" INT

# init
# wait
# ut_build_run
# ut_check_status
# release_build
# release_check_status
STATE="init"
CHECK_STATUS_RVAL=1

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

function state_init() {
    echo "Started watching path: "
    echo $INOTIFY_PATH | tr "[:blank:]" "\n"
    cp /home/joker/sync/src/extern/llvm/Release+Asserts/lib/libclang.so build/
    cp /home/joker/sync/src/extern/llvm/Release+Asserts/lib/libclang.so ./
}

function state_wait() {
    echo -e "${C_YELLOW}================================${C_NONE}"
    IFILES=$(inotifywait -q -r -e MOVE_SELF -e MODIFY -e ATTRIB -e CREATE --format %w $INOTIFY_PATH)
    echo "Change detected in: $IFILES"
    sleep 1
}

function state_ut_build_run() {
    dub build -c unittest -b unittest
    check_status "Compile UnitTest"

    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        dub run -b unittest
        check_status "Run UnitTest"
    fi
}

function state_release_build() {
    dub build
    check_status "Compile Release"
}

function play_sound() {
    # mplayer /usr/share/sounds/KDE-Sys-App-Error.ogg 2>/dev/null >/dev/null
    if [[ "$1" = "ok" ]]; then
        mplayer /usr/share/sounds/KDE-Sys-App-Positive.ogg 2>/dev/null >/dev/null
    else
        mplayer /usr/share/sounds/KDE-Sys-App-Negative.ogg 2>/dev/null >/dev/null
    fi
}

function watch_tests() {
while :
do
    echo "State $STATE"
    case "$STATE" in
        "init")
            state_init
            STATE="wait"
            ;;
        "wait")
            state_wait
            STATE="ut_build_run"
            ;;
        "ut_build_run")
            state_ut_build_run
            STATE="ut_check_status"
            ;;
        "ut_check_status")
            if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
                STATE="release_build"
            else
                play_sound "fail"
                STATE="wait"
            fi
            ;;
        "release_build")
            state_release_build
            STATE="release_check_status"
            ;;
        "release_check_status")
            STATE="wait"
            if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
                play_sound "ok"
            else
                play_sound "fail"
            fi
            ;;
        *) echo "Unknown state $STATE"
            exit 1
            ;;
    esac
done
}

watch_tests

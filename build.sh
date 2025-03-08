#!/bin/sh

# Error on unset variables.
set -u

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--Wall -Wextra -Wpedantic -Wconversion -Wswitch-enum -Wmissing-prototypes}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:-}"
ALL_CFLAGS="$CFLAGS $EXTRA_CFLAGS -std=c11"

source=play-music.c

set -x

# Automatically format if astyle is installed.
if type astyle > /dev/null 2>&1; then
    astyle -n --style=attach "$source" || exit 1
fi
# shellcheck disable=SC2086 # We want $ALL_CFLAGS to wordsplit.
$CC $ALL_CFLAGS -o play-music "$source" || exit 1

#!/bin/sh

# This file is part of play-music.
#
# Copyright (c) 2025 ona-li-toki-e-jan-Epiphany-tawa-mi
#
# play-music is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# play-music is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# play-music. If not, see <https://www.gnu.org/licenses/>.

# Error on unset variables.
set -u

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--Wall -Wextra -Wpedantic -Wconversion -Wswitch-enum -Wmissing-prototypes}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:-}"
ALL_CFLAGS="$CFLAGS $EXTRA_CFLAGS -std=c11 -Iinclude/"

source=play-music.c

set -x

# Automatically format if astyle is installed.
if type astyle > /dev/null 2>&1; then
    astyle -n --style=attach "$source" || exit 1
fi
# shellcheck disable=SC2086 # We want $ALL_CFLAGS to wordsplit.
$CC $ALL_CFLAGS -o play-music "$source" || exit 1

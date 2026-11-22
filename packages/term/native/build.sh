#!/bin/sh
set -eu

mkdir -p build
object=$(mktemp build/terminal-linux.XXXXXXXX.o)
trap 'if [ -f "$object" ]; then unlink "$object"; fi' EXIT

# DUB passes D LDC sanitizer flags through DFLAGS for the sanitizer lane.
# Instrument this package's C boundary as part of the same linked test.
case " ${DFLAGS:-} " in
    *" -fsanitize=address "*)
        set -- -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer
        ;;
    *)
        set -- -O2
        ;;
esac

"${CC:-cc}" -std=c11 -Wall -Wextra -Wpedantic -Werror -fPIC "$@" -c native/linux.c -o "$object"
mv "$object" build/terminal-linux.o

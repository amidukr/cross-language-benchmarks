#!/bin/sh
exec "$(dirname "$0")/../scripts/build_native.sh" javascript "$@"

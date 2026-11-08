#!/bin/sh
exec "$(dirname "$0")/../scripts/build_assembly_native.sh" python "$@"

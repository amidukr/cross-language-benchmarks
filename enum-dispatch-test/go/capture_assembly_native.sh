#!/bin/sh
exec "$(dirname "$0")/../scripts/capture_assembly_native.sh" go "$@"

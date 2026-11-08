#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
exec "$root/scripts/all-targets.sh" build-docker "$@"

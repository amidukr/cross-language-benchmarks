#!/usr/bin/env bash
set -euo pipefail
language=${1:?language required}
shift
target= profile=assembly
while (($#)); do case $1 in --target)
    target=${2:?}
    shift 2
    ;;
--diagnostic-profile)
    profile=${2:?}
    shift 2
    ;;
--help) exit 0 ;; *)
    echo "unknown option: $1" >&2
    exit 2
    ;;
esac done
[[ $profile =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 2
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
"$root/$language/build_native.sh" --target "$target"
echo "reusing exact native performance artifact for profile $profile" >&2

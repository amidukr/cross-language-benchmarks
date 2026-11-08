#!/usr/bin/env bash
set -euo pipefail
action=${1:?action required}; shift
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
languages=(c c cpp cpp java java java rust go python csharp csharp javascript)
targets=(c-gcc c-clang cpp-gcc cpp-clang temurin-c2 graalvm-jit graalvm-native rust go cpython coreclr dotnet-native node-v8)
profile=assembly; run_id=
forwarded=("$@")
for ((i=0;i<${#forwarded[@]};i+=2)); do
 [[ ${forwarded[i]} == --diagnostic-profile ]] && profile=${forwarded[i+1]}
 [[ ${forwarded[i]} == --diagnostic-run-id ]] && run_id=${forwarded[i+1]}
done
[[ $action == build || -n $run_id ]] || { echo "--diagnostic-run-id is required" >&2; exit 2; }
succeeded=(); failed=()
for i in "${!targets[@]}"; do
 echo "$action ${targets[i]}" >&2
 set +e
 if [[ $action == build ]]; then
   "$root/${languages[i]}/build_assembly.sh" --target "${targets[i]}" --diagnostic-profile "$profile"
 else
   "$root/${languages[i]}/capture_assembly.sh" --target "${targets[i]}" "${forwarded[@]}"
 fi
 status=$?; set -e
 if ((status==0)); then succeeded+=("${targets[i]}"); else failed+=("${targets[i]} (exit $status)"); fi
done
printf 'succeeded (%d): %s\n' "${#succeeded[@]}" "${succeeded[*]:-none}" >&2
printf 'failed (%d): %s\n' "${#failed[@]}" "${failed[*]:-none}" >&2
((${#failed[@]}==0))

#!/usr/bin/env bash
set -euo pipefail
action=${1:?}
shift
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
languages=(c c cpp cpp java java java rust go python csharp csharp javascript)
targets=(c-gcc c-clang cpp-gcc cpp-clang temurin-c2 graalvm-jit graalvm-native rust go cpython coreclr dotnet-native node-v8)
profile=assembly
run_id=
forwarded=("$@")
for ((i = 0; i < ${#forwarded[@]}; i += 2)); do
    [[ ${forwarded[i]} == --diagnostic-profile ]] && profile=${forwarded[i + 1]}
    [[ ${forwarded[i]} == --diagnostic-run-id ]] && run_id=${forwarded[i + 1]}
done
[[ $action == build || -n $run_id ]] || {
    echo "--diagnostic-run-id is required" >&2
    exit 2
}
ok=()
skipped=()
failed=()
for i in "${!targets[@]}"; do
    set +e
    if [[ $action == build ]]; then "$root/${languages[i]}/build_assembly_native.sh" --target "${targets[i]}" --diagnostic-profile "$profile"; else "$root/${languages[i]}/capture_assembly_native.sh" --target "${targets[i]}" "${forwarded[@]}"; fi
    s=$?
    set -e
    if ((s == 0)); then ok+=("${targets[i]}"); elif ((s == 127)); then skipped+=("${targets[i]}"); else failed+=("${targets[i]} ($s)"); fi
done
printf 'succeeded (%d): %s\n' "${#ok[@]}" "${ok[*]:-none}" >&2
printf 'skipped (%d): %s\n' "${#skipped[@]}" "${skipped[*]:-none}" >&2
printf 'failed (%d): %s\n' "${#failed[@]}" "${failed[*]:-none}" >&2
((${#failed[@]} == 0 && ${#ok[@]} > 0))

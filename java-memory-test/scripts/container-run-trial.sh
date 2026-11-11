#!/usr/bin/env bash
set -uo pipefail

output=/output
mkdir -p "$output"
app=${MEMORY_APP:?MEMORY_APP is required}
target=${MEMORY_TARGET:?MEMORY_TARGET is required}
collector=${MEMORY_COLLECTOR:?MEMORY_COLLECTOR is required}
heap_profile=${MEMORY_HEAP_PROFILE:?MEMORY_HEAP_PROFILE is required}
heap_initial=${MEMORY_HEAP_INITIAL:-}
heap_max=${MEMORY_HEAP_MAX:-}
run_id=${MEMORY_RUN_ID:?MEMORY_RUN_ID is required}
trial=${MEMORY_TRIAL:?MEMORY_TRIAL is required}
image_ref=${MEMORY_IMAGE_REF:-unknown}
image_id=${MEMORY_IMAGE_ID:-unknown}
engine=${MEMORY_CONTAINER_ENGINE:-unknown}
engine_version=${MEMORY_CONTAINER_ENGINE_VERSION:-unknown}
host_environment=${MEMORY_HOST_ENVIRONMENT:-unknown}

manifest="$output/manifest.txt"
raw="$output/raw-samples.csv"
results="$output/results.csv"
: >"$output/app.stdout"
: >"$output/app.stderr"
cp /opt/toolchain-version.txt "$output/toolchain-version.txt"
cp /opt/xvfb-version.txt "$output/xvfb-version.txt"
cp /opt/os-packages.txt "$output/os-packages.txt"

monotonic_ns() {
  awk '{printf "%.0f\n", $1 * 1000000000}' /proc/uptime
}

record_manifest() {
  printf '%s=%s\n' "$1" "$2" >>"$manifest"
}

: >"$manifest"
record_manifest schema_version 1
record_manifest run_id "$run_id"
record_manifest application "$app"
record_manifest target "$target"
record_manifest execution_kind "$EXECUTION_KIND"
record_manifest collector "$collector"
record_manifest build_collector "$MEMORY_BUILD_COLLECTOR"
record_manifest heap_profile "$heap_profile"
record_manifest requested_xms "${heap_initial:-default}"
record_manifest requested_xmx "${heap_max:-default}"
record_manifest trial "$trial"
record_manifest container_id "$(hostname)"
record_manifest image "$image_ref"
record_manifest image_id "$image_id"
record_manifest container_engine "$engine"
record_manifest container_engine_version "$engine_version"
record_manifest cpu_limit "one logical CPU"
record_manifest memory_limit_bytes 1073741824
record_manifest architecture "$(uname -m)"
record_manifest kernel "$(uname -sr)"
record_manifest host_environment "$host_environment"
record_manifest started_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record_manifest ready_timeout_seconds 120
record_manifest idle_sample_interval_ms 100
record_manifest idle_sample_duration_seconds 30
record_manifest quiescence_seconds 10
record_manifest rest_request_count 1000
record_manifest probe_only "${MEMORY_PROBE_ONLY:-false}"
duration_mode=${MEMORY_DURATION_MODE:-full}
record_manifest duration_mode "$duration_mode"

echo 'monotonic_ns,elapsed_from_ready_ns,phase,sample,process_rss_bytes,process_hwm_bytes,cgroup_memory_bytes,rss_source,pid_start_ticks' >"$raw"
echo 'schema_version,run_id,benchmark,case_id,language,target,config_id,toolchain,flags,environment,trial,phase,sample,elapsed_ms,metric,value,unit' >"$results"

app_pid=
xvfb_pid=
cleanup() {
  local controller_status=$?
  if ! grep -q '^status=' "$manifest" 2>/dev/null; then
    record_manifest status failed
    record_manifest failure_reason "controller-exit-$controller_status"
  fi
  if [[ -n ${app_pid:-} ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill -TERM "$app_pid" 2>/dev/null || true
    for _ in {1..100}; do
      kill -0 "$app_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$app_pid" 2>/dev/null; then
      record_manifest forced_sigkill true
      kill -KILL "$app_pid" 2>/dev/null || true
    fi
    wait "$app_pid" 2>/dev/null || true
  fi
  if [[ -f $output/xvfb.pid ]]; then
    xvfb_pid=$(<"$output/xvfb.pid")
    kill -TERM "$xvfb_pid" 2>/dev/null || true
  fi
  return "$controller_status"
}
trap cleanup EXIT INT TERM

/opt/memory-test/container-launch.sh >"$output/app.stdout" 2>"$output/app.stderr" &
app_pid=$!
record_manifest application_pid "$app_pid"
if [[ ! -r /proc/$app_pid/stat ]]; then
  record_manifest status failed
  record_manifest failure_reason process-stat-unavailable
  exit 1
fi
pid_start_ticks=$(awk '{print $22}' "/proc/$app_pid/stat")
record_manifest process_start_ticks "$pid_start_ticks"
start_ns=$(monotonic_ns)

ready=false
for _ in {1..1200}; do
  if grep -q '^MEMORY_TEST_READY ' "$output/app.stdout"; then
    ready=true
    break
  fi
  if ! kill -0 "$app_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
ready_ns=$(monotonic_ns)
readiness_ms=$(((ready_ns - start_ns) / 1000000))
record_manifest readiness_time_ms "$readiness_ms"
if [[ $ready != true ]]; then
  record_manifest status failed
  record_manifest failure_reason readiness-timeout-or-process-exit
  wait "$app_pid" 2>/dev/null
  record_manifest application_exit_status "$?"
  exit 1
fi
record_manifest readiness_marker "$(grep '^MEMORY_TEST_READY ' "$output/app.stdout" | head -n 1)"
if grep -q '^MEMORY_TEST_HEAP ' "$output/app.stdout"; then
  heap_line=$(grep '^MEMORY_TEST_HEAP ' "$output/app.stdout" | head -n 1)
  record_manifest effective_heap "$heap_line"
fi
if [[ $EXECUTION_KIND == jvm && -s $output/gc.log ]]; then
  selected_gc=$(grep -m1 -E 'Using .*GC|Collector:' "$output/gc.log" || true)
  record_manifest selected_collector "${selected_gc:-not-reported-by-runtime}"
else
  record_manifest selected_collector "native-build-$MEMORY_BUILD_COLLECTOR"
fi

if [[ ${MEMORY_PROBE_ONLY:-false} == true ]]; then
  if [[ $app == spring-boot || $app == quarkus ]]; then
    response=$(curl --silent --show-error --max-time 5 --write-out $'\n%{http_code}\n%{content_type}' \
      http://127.0.0.1:8080/hello-world) || response=
    body=${response%%$'\n'*}
    rest=${response#*$'\n'}
    status_code=${rest%%$'\n'*}
    content_type=${rest#*$'\n'}
    if [[ $body != 'Hello World' || $status_code != 200 || $content_type != text/plain* ]];
    then
      record_manifest status failed
      record_manifest failure_reason probe-readiness-check-failed
      exit 1
    fi
  fi
  record_manifest request_count 1
  record_manifest request_failures 0
  record_manifest probe_completed true
  kill -TERM "$app_pid" 2>/dev/null || true
  for _ in {1..100}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  wait "$app_pid" 2>/dev/null
  app_status=$?
  app_pid=
  record_manifest application_exit_status "$app_status"
  record_manifest forced_sigkill false
  record_manifest completed_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  record_manifest status success
  trap - EXIT INT TERM
  exit 0
fi

case "$app" in
  spring-boot|quarkus)
    endpoint_ready=false
    body=
    content_type=
    for _ in {1..1200}; do
      if body=$(curl --silent --fail --max-time 5 \
          --dump-header "$output/readiness-headers.txt" \
          http://127.0.0.1:8080/hello-world 2>/dev/null); then
        content_type=$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{gsub("\r",""); sub(/^[^:]+:[[:space:]]*/,""); print; exit}' "$output/readiness-headers.txt")
        if [[ $body == 'Hello World' && $content_type == text/plain* ]]; then
          endpoint_ready=true
          break
        fi
      fi
      kill -0 "$app_pid" 2>/dev/null || break
      sleep 0.1
    done
    if [[ $endpoint_ready != true ]]; then
      record_manifest status failed
      record_manifest failure_reason endpoint-readiness-or-response-failed
      record_manifest observed_content_type "${content_type:-unavailable}"
      printf '%s' "$body" >"$output/readiness-body.txt"
      exit 1
    fi
    ;;
esac

cgroup_file=/sys/fs/cgroup/memory.current
[[ -r $cgroup_file ]] || cgroup_file=/sys/fs/cgroup/memory/memory.usage_in_bytes

sample_number=0
sample_once() {
  local phase=$1 now elapsed current_ticks rss hwm cgroup source elapsed_ms flags
  now=$(monotonic_ns)
  elapsed=$((now - ready_ns))
  if [[ ! -r /proc/$app_pid/stat ]]; then return 1; fi
  current_ticks=$(awk '{print $22}' "/proc/$app_pid/stat")
  if [[ $current_ticks != "$pid_start_ticks" ]]; then
    record_manifest status failed
    record_manifest failure_reason pid-reuse-detected
    return 1
  fi
  if [[ -r /proc/$app_pid/smaps_rollup ]]; then
    rss=$(awk '/^Rss:/{print $2 * 1024; exit}' "/proc/$app_pid/smaps_rollup")
    source=smaps_rollup
  else
    rss=$(awk '/^VmRSS:/{print $2 * 1024; exit}' "/proc/$app_pid/status")
    source=status-vmrss
  fi
  hwm=$(awk '/^VmHWM:/{print $2 * 1024; exit}' "/proc/$app_pid/status")
  cgroup=$(<"$cgroup_file")
  [[ $rss =~ ^[0-9]+$ && $hwm =~ ^[0-9]+$ && $cgroup =~ ^[0-9]+$ ]] || return 1
  ((sample_number += 1))
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$now" "$elapsed" "$phase" "$sample_number" "$rss" "$hwm" "$cgroup" "$source" "$current_ticks" >>"$raw"
  elapsed_ms=$((elapsed / 1000000))
  flags="collector=$collector;xms=${heap_initial:-default};xmx=${heap_max:-default}"
  for metric_value in "rss_bytes:$rss" "peak_rss_bytes:$hwm" "cgroup_memory_bytes:$cgroup"; do
    printf '2,%s,java-memory,%s,Java,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,bytes\n' \
      "$run_id" "$app" "$target" "$heap_profile-$collector" "$target" "$flags" \
      "$host_environment" "$trial" "$phase" "$sample_number" "$elapsed_ms" \
      "${metric_value%%:*}" "${metric_value#*:}" >>"$results"
  done
}

printf '2,%s,java-memory,%s,Java,%s,%s,%s,%s,%s,%s,startup,1,%s,readiness_time_ms,%s,ms\n' \
  "$run_id" "$app" "$target" "$heap_profile-$collector" "$target" \
  "collector=$collector;xms=${heap_initial:-default};xmx=${heap_max:-default}" \
  "$host_environment" "$trial" "$readiness_ms" "$readiness_ms" >>"$results"
if [[ -n ${heap_line:-} ]]; then
  for heap_metric in init:heap_init_bytes used:heap_used_bytes committed:heap_committed_bytes max:heap_max_bytes; do
    heap_key=${heap_metric%%:*}
    heap_name=${heap_metric#*:}
    heap_value=$(printf '%s\n' "$heap_line" | sed -n "s/.* $heap_key=\\([-0-9]*\\).*/\\1/p")
    [[ $heap_value =~ ^-?[0-9]+$ ]] || continue
    printf '2,%s,java-memory,%s,Java,%s,%s,%s,%s,%s,%s,startup,1,%s,%s,%s,bytes\n' \
      "$run_id" "$app" "$target" "$heap_profile-$collector" "$target" \
      "collector=$collector;xms=${heap_initial:-default};xmx=${heap_max:-default}" \
      "$host_environment" "$trial" "$readiness_ms" "$heap_name" "$heap_value" >>"$results"
  done
fi

request_failures=0
if [[ $duration_mode == full ]]; then
  for _ in {1..300}; do sample_once ready-idle || exit 1; sleep 0.1; done
fi
if [[ $app == spring-boot || $app == quarkus ]]; then
  for request in {1..1000}; do
    response=$(curl --silent --show-error --max-time 5 --write-out $'\n%{http_code}\n%{content_type}' \
      http://127.0.0.1:8080/hello-world) || response=$'\n000\n'
    body=${response%%$'\n'*}
    rest=${response#*$'\n'}
    code=${rest%%$'\n'*}
    type=${rest#*$'\n'}
    if [[ $body != 'Hello World' || $code != 200 || $type != text/plain* ]]; then
      ((request_failures += 1))
    fi
    if (( request % 100 == 0 )); then sample_once exercise || exit 1; fi
  done
fi
record_manifest request_count "$([[ $app == spring-boot || $app == quarkus ]] && echo 1000 || echo 0)"
record_manifest request_failures "$request_failures"
if (( request_failures != 0 )); then
  record_manifest status failed
  record_manifest failure_reason request-correctness-failure
  exit 1
fi

if [[ $duration_mode == survey ]]; then
  for _ in {1..100}; do sample_once survey-idle || exit 1; sleep 0.1; done
else
  sleep 10
  for _ in {1..300}; do sample_once post-exercise-idle || exit 1; sleep 0.1; done
fi

kill -TERM "$app_pid" 2>/dev/null || true
shutdown_clean=false
for _ in {1..100}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then shutdown_clean=true; break; fi
  sleep 0.1
done
if [[ $shutdown_clean == false ]]; then
  record_manifest forced_sigkill true
  kill -KILL "$app_pid" 2>/dev/null || true
else
  record_manifest forced_sigkill false
fi
wait "$app_pid" 2>/dev/null
app_status=$?
app_pid=
record_manifest application_exit_status "$app_status"
record_manifest completed_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record_manifest status success
trap - EXIT INT TERM
exit 0

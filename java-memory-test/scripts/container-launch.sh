#!/usr/bin/env bash
set -euo pipefail

for ambient_name in JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS; do
  if [[ -n ${!ambient_name:-} ]]; then
    echo "ambient runtime option is not allowed: $ambient_name" >&2
    exit 2
  fi
done

app=${MEMORY_APP:?MEMORY_APP is required}
kind=${EXECUTION_KIND:?EXECUTION_KIND is required}
collector=${MEMORY_COLLECTOR:?MEMORY_COLLECTOR is required}
heap_initial=${MEMORY_HEAP_INITIAL:-}
heap_max=${MEMORY_HEAP_MAX:-}

jvm_options=()
case "$collector" in
  default) ;;
  serial) jvm_options+=("-XX:+UseSerialGC") ;;
  parallel) jvm_options+=("-XX:+UseParallelGC") ;;
  g1) jvm_options+=("-XX:+UseG1GC") ;;
  zgc) jvm_options+=("-XX:+UseZGC") ;;
  shenandoah) jvm_options+=("-XX:+UseShenandoahGC") ;;
  epsilon) jvm_options+=("-XX:+UnlockExperimentalVMOptions" "-XX:+UseEpsilonGC") ;;
  *) echo "unsupported collector: $collector" >&2; exit 2 ;;
esac
jvm_options+=("-Xlog:gc+init=info,gc=info:file=/output/gc.log:time,level,tags")
[[ -z $heap_initial ]] || jvm_options+=("-Xms$heap_initial")
[[ -z $heap_max ]] || jvm_options+=("-Xmx$heap_max")

if [[ $app == swing ]]; then
  export DISPLAY=:99
  Xvfb :99 -screen 0 1024x768x24 -nolisten tcp >/output/xvfb.stdout 2>/output/xvfb.stderr &
  echo "$!" >/output/xvfb.pid
fi

if [[ $kind == native ]]; then
  native_options=()
  [[ -z $heap_initial ]] || native_options+=("-Xms$heap_initial")
  [[ -z $heap_max ]] || native_options+=("-Xmx$heap_max")
  exec /opt/apps/app "${native_options[@]}"
fi

case "$app" in
  console) exec java "${jvm_options[@]}" -cp /opt/apps/console ConsoleHello ;;
  swing) exec java "${jvm_options[@]}" -cp /opt/apps/swing SwingHello ;;
  spring-boot) exec java "${jvm_options[@]}" -jar /opt/apps/spring-boot/app.jar ;;
  quarkus) exec java "${jvm_options[@]}" -jar /opt/apps/quarkus/quarkus-run.jar ;;
  *) echo "unsupported application: $app" >&2; exit 2 ;;
esac

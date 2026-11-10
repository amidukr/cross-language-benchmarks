#!/usr/bin/env bash

memory_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(cd -- "$memory_root/.." && pwd)

die() {
  echo "$*" >&2
  exit 2
}

require_id() {
  [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid $1: $2"
}

require_application() {
  case "$1" in console|swing|spring-boot|quarkus) ;; *) die "invalid application: $1" ;; esac
}

require_target() {
  case "$1" in temurin-c2|graalvm-jit|graalvm-native) ;; *) die "invalid target: $1" ;; esac
}

require_collector() {
  case "$1" in default|serial|parallel|g1|zgc|shenandoah|epsilon) ;; *) die "invalid collector: $1" ;; esac
}

require_heap_value() {
  [[ -z $2 || $2 =~ ^[1-9][0-9]*[kKmMgG]$ ]] || die "invalid $1: $2"
}

select_engine() {
  container_engine=${CONTAINER_ENGINE:-docker}
  case "$container_engine" in docker|podman) ;; *) die "unsupported CONTAINER_ENGINE: $container_engine" ;; esac
  command -v "$container_engine" >/dev/null 2>&1 || {
    echo "container engine not found: $container_engine" >&2
    exit 127
  }
  container_engine_version=$("$container_engine" --version 2>&1)
  case "$container_engine:$container_engine_version" in
    podman:*|*:*[Pp]odman*) container_runtime=podman ;;
    *) container_runtime=docker ;;
  esac
}

image_for() {
  local app=$1 target=$2 collector=$3
  if [[ $target == graalvm-native ]]; then
    printf 'java-memory-%s-%s-%s:latest\n' "$app" "$target" "$collector"
  else
    printf 'java-memory-%s-%s:latest\n' "$app" "$target"
  fi
}

absolute_directory() {
  mkdir -p "$1"
  (cd -- "$1" && pwd)
}

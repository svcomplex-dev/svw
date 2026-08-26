#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 code@svcomplex.ai
# Build the independently maintained waveform bridge against a local reader SDK.
set -euo pipefail

repository=https://github.com/svcomplex-dev/svw-wave-bridge.git
revision=main
reader_root=
source_root=
output=$PWD/libsvw-wave-bridge.so
host_output=
jobs=${SVW_BRIDGE_JOBS:-}

usage() {
    cat <<'EOF'
usage: build-svw-wave-bridge.sh --reader-root DIR [options]

Options:
  --reader-root DIR  Reader SDK directory containing ffrAPI.h and linux64/
  --source DIR       Use an existing svw-wave-bridge checkout
  --repository URL   Source URL (default: public svcomplex-dev repository)
  --revision REV     Exact commit or ref to build (default: main)
  --output FILE      Output shared library (default: ./libsvw-wave-bridge.so)
  --host-output FILE Output loader host (default: next to the shared library)
  --jobs N           Parallel make jobs
EOF
}

fail() {
    printf 'build-svw-wave-bridge: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --reader-root) reader_root=${2:?missing value}; shift 2 ;;
        --source) source_root=${2:?missing value}; shift 2 ;;
        --repository) repository=${2:?missing value}; shift 2 ;;
        --revision) revision=${2:?missing value}; shift 2 ;;
        --output) output=${2:?missing value}; shift 2 ;;
        --host-output) host_output=${2:?missing value}; shift 2 ;;
        --jobs) jobs=${2:?missing value}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
done

[ "$(uname -s)" = Linux ] || fail "the current bridge output is Linux-only"
[ -n "$reader_root" ] || fail "--reader-root is required"
case $reader_root in /*) ;; *) reader_root=$PWD/$reader_root ;; esac
case $output in /*) ;; *) output=$PWD/$output ;; esac
if [ -z "$host_output" ]; then
    host_output=$(dirname "$output")/svw-wave-bridge-host
else
    case $host_output in /*) ;; *) host_output=$PWD/$host_output ;; esac
fi
[ "$output" != "$host_output" ] || fail "library and host outputs must differ"
[ -f "$reader_root/ffrAPI.h" ] || fail "missing $reader_root/ffrAPI.h"
reader_lib=$reader_root/linux64
[ -f "$reader_lib/libnffr.so" ] || fail "missing $reader_lib/libnffr.so"
[ -f "$reader_lib/libnsys.so" ] || fail "missing $reader_lib/libnsys.so"

temporary=
cleanup() {
    [ -z "$temporary" ] || rm -rf "$temporary"
}
trap cleanup EXIT

if [ -z "$source_root" ]; then
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/svw-wave-bridge.XXXXXX")
    source_root=$temporary/source
    git clone --no-checkout "$repository" "$source_root"
    (cd "$source_root" && git fetch --depth=1 origin "$revision")
    (cd "$source_root" && git checkout --detach FETCH_HEAD)
else
    case $source_root in /*) ;; *) source_root=$PWD/$source_root ;; esac
    [ -d "$source_root/.git" ] || fail "--source must be a Git checkout"
    resolved=$(cd "$source_root" && git rev-parse "$revision^{commit}")
    [ "$(cd "$source_root" && git rev-parse HEAD)" = "$resolved" ] ||
        fail "--source HEAD does not match --revision"
fi

case $revision in
    main) ;;
    *)
        printf '%s\n' "$revision" | grep -Eq '^[0-9a-f]{40}$' ||
            fail "--revision must be main or an exact 40-character commit"
        [ "$(cd "$source_root" && git rev-parse HEAD)" = "$revision" ] ||
            fail "the fetched bridge revision does not match"
        ;;
esac
[ -z "$(cd "$source_root" && git status --porcelain --untracked-files=all)" ] ||
    fail "bridge source checkout is not clean"

if [ -z "$jobs" ]; then
    jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n')
fi
printf '%s\n' "$jobs" | grep -Eq '^[1-9][0-9]*$' || fail "--jobs must be positive"
cxx=${CXX:-c++}
zlib_library=$($cxx -print-file-name=libz.so.1)
[ -f "$zlib_library" ] || fail "the system libz.so.1 runtime was not found"

make -C "$source_root" -j "$jobs" \
    CXX="$cxx" \
    CXXFLAGS='-O3 -DNDEBUG' \
    READER_INCLUDE="$reader_root" \
    READER_LDFLAGS="-L$reader_lib -Wl,-rpath,$reader_lib -Wl,-z,defs" \
    READER_LIBS="-lnffr -lnsys $zlib_library -lpthread -ldl -lm"

library=$source_root/build/libsvw-wave-bridge.so
host=$source_root/build/svw-wave-bridge-host
[ -s "$library" ] || fail "bridge build did not produce $library"
[ -x "$host" ] || fail "bridge build did not produce $host"
command -v nm >/dev/null 2>&1 || fail "nm is required to audit the bridge output"
nm -D --defined-only "$library" | grep -Eq '[[:space:]]svw_wave_bridge_entry_v1$' ||
    fail "bridge ABI entry is missing"
file "$host" | grep -q 'ELF 64-bit.*x86-64' || fail "bridge host is not Linux x86-64 ELF"
host_dependencies=$(ldd "$host")
printf '%s\n' "$host_dependencies" |
    grep -Eq 'libnffr|libnsys|not found' && fail "bridge host has an invalid runtime dependency"
if host_error=$("$host" --svw-wave-bridge-host=1 relative-library.so 2>&1); then
    fail "bridge host accepted a relative library path"
fi
if ! printf '%s\n' "$host_error" | grep -q 'must be absolute'; then
    fail "bridge host invocation contract failed"
fi
mkdir -p "$(dirname "$output")" "$(dirname "$host_output")"
install -m 0755 "$library" "$output"
install -m 0755 "$host" "$host_output"
printf 'svw wave bridge: %s\n' "$output"
printf 'svw wave bridge host: %s\n' "$host_output"

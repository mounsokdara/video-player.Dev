#!/usr/bin/env bash
# Reproducible builds: the jni package links libdartjni.so with a GNU build-id that is a hash of the
# UNSTRIPPED binary, which embeds the NDK's absolute path (differs between CI and the F-Droid buildserver).
# Linking with --build-id=none removes that environment-dependent stamp.
# Called by the F-Droid recipe and by the GitHub Actions F-Droid job, so both build identically.
set -euo pipefail
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
patched=0
for f in "$PUB_CACHE"/hosted/pub.dev/jni-[0-9]*/src/CMakeLists.txt; do
  [ -f "$f" ] || continue
  grep -q 'build-id=none' "$f" || sed -i '/^project(/a add_link_options("LINKER:--build-id=none")' "$f"
  grep -q 'build-id=none' "$f" || { echo "failed to patch $f" >&2; exit 1; }
  echo "patched $f"; patched=$((patched + 1))
done
[ "$patched" -gt 0 ] || { echo "jni CMakeLists.txt not found under $PUB_CACHE" >&2; exit 1; }

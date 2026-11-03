#!/usr/bin/env bash
# Builds decode-only FFmpeg (LGPL, static) for Android: just the HEVC and H.264 decoders, no
# demuxers, filters, network or encoders. Our own engine does demuxing, sync and rendering; this is
# only the software video decoder used for streams the phone's chip cannot decode (e.g. 10-bit HEVC).
#
# Usage: scripts/build_ffmpeg.sh [abi ...]      (default: arm64-v8a armeabi-v7a x86_64)
# Output: android/app/src/main/cpp/ffmpeg/<abi>/{include,lib}
# Needs the Android NDK (ANDROID_NDK_LATEST_HOME or ANDROID_NDK_HOME) and git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_BASE="$ROOT/android/app/src/main/cpp/ffmpeg"
SRC="$ROOT/.ffmpeg-src"
TAG="n7.1"
API=24

NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}"
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then echo "Android NDK not found (set ANDROID_NDK_HOME)"; exit 1; fi
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
echo "NDK=$NDK"

ABIS=("$@")
[ ${#ABIS[@]} -eq 0 ] && ABIS=(arm64-v8a armeabi-v7a x86_64)

if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch "$TAG" https://github.com/FFmpeg/FFmpeg.git "$SRC"
fi

build_abi() {
  local abi="$1" arch cpu triple extra=""
  case "$abi" in
    arm64-v8a)   arch=aarch64; cpu=armv8-a;  triple=aarch64-linux-android;;
    armeabi-v7a) arch=arm;     cpu=armv7-a;  triple=armv7a-linux-androideabi
                 extra="-march=armv7-a -mfpu=neon -mfloat-abi=softfp";;
    x86_64)      arch=x86_64;  cpu=x86-64;   triple=x86_64-linux-android;;
    *) echo "unknown ABI $abi"; exit 1;;
  esac
  local out="$OUT_BASE/$abi" build="$SRC/build-$abi"
  rm -rf "$out" "$build"; mkdir -p "$build"
  cd "$build"
  local asmflags="--enable-neon --enable-asm"
  [ "$abi" = "x86_64" ] && asmflags="--disable-x86asm"   # avoids needing nasm; x86_64 is only emulators/Chromebooks
  "$SRC/configure" \
    --prefix="$out" \
    --enable-cross-compile --target-os=android --arch="$arch" --cpu="$cpu" \
    --cc="$TC/bin/${triple}${API}-clang" --cxx="$TC/bin/${triple}${API}-clang++" \
    --ar="$TC/bin/llvm-ar" --nm="$TC/bin/llvm-nm" --ranlib="$TC/bin/llvm-ranlib" --strip="$TC/bin/llvm-strip" \
    --sysroot="$TC/sysroot" \
    --disable-everything --disable-autodetect --disable-programs --disable-doc --disable-debug --disable-network \
    --disable-avdevice --disable-avformat --disable-avfilter --disable-swscale --disable-swresample --disable-postproc \
    --enable-avcodec --enable-avutil \
    --enable-decoder=hevc --enable-decoder=h264 --enable-parser=hevc --enable-parser=h264 \
    --enable-pthreads $asmflags \
    --enable-static --disable-shared --enable-pic \
    --extra-cflags="-O3 -fPIC $extra -ffile-prefix-map=$SRC=. -ffile-prefix-map=$NDK=ndk" \
    --extra-ldflags="-Wl,--build-id=none"
  make -j"$(nproc)"
  make install
  cd "$ROOT"
  ls -la "$out/lib"
}

for abi in "${ABIS[@]}"; do
  echo "=== FFmpeg $TAG for $abi ==="
  build_abi "$abi"
done

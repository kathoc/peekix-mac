#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFIX="$REPO_ROOT/Vendor/ffmpeg"
FFMPEG_VERSION="n6.1.1"
BUILD_DIR="$REPO_ROOT/.ffmpeg-build"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d ffmpeg ]; then
    git clone --depth 1 --branch "$FFMPEG_VERSION" https://github.com/FFmpeg/FFmpeg.git ffmpeg
fi

cd ffmpeg

mkdir -p "$PREFIX"

./configure \
  --prefix="$PREFIX" \
  --arch=arm64 --target-os=darwin \
  --enable-cross-compile --cc=clang \
  --enable-static --disable-shared \
  --disable-programs --disable-doc --disable-htmlpages --disable-manpages \
  --disable-everything \
  --enable-protocol=file,tcp,udp,rtp,rtsp \
  --enable-demuxer=rtsp,rtp,h264,hevc,mpegts \
  --enable-parser=h264,hevc,aac \
  --enable-decoder=h264,hevc,aac \
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb \
  --disable-debug --enable-pic \
  --extra-cflags="-mmacosx-version-min=13.0 -arch arm64 -O2"

make -j"$(sysctl -n hw.ncpu)"
make install

echo "FFmpeg build complete. Libs in $PREFIX/lib/"
ls -lh "$PREFIX/lib/"*.a

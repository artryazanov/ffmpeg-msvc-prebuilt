#!/bin/bash
# Copyright (c) 2024 System233
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

HELP_MSG="Usage: build.sh <x86,amd64,arm,arm64> [static,shared] [gpl,lgpl] ...FF_ARGS"
set -e
source ./env.sh

if [ -z $BUILD_ARCH ]; then
    echo "$HELP_MSG" >&2
    exit 1
fi

shift 3 || true
FF_ARGS=$@

for dep in libharfbuzz libfreetype sdl libjxl libvpx libwebp libass; do
    if grep -q "enable-${dep}" FFmpeg/configure; then
        export ENABLE_${dep^^}=1
        # FF_ARGS="$FF_ARGS --enable-$dep"
    fi
done

echo BUILD_ARCH=$BUILD_ARCH
echo BUILD_TYPE=$BUILD_TYPE
echo BUILD_LICENSE=$BUILD_LICENSE
echo FF_ARGS=$FF_ARGS

add_ffargs() {
    FF_ARGS="$FF_ARGS $@"
}

apply-patch() {
    GIT_CMD="git -C $1 apply $(pwd)/patches/$2 --ignore-whitespace"
    if ! $GIT_CMD -R --check 2>/dev/null; then
        echo Apply $2 for $1
        $GIT_CMD
    else
        echo Skip $2 for $1
    fi
}

apply-patch zlib zlib.patch
# apply-patch FFmpeg ffmpeg.patch
apply-patch harfbuzz harfbuzz.patch

./build-make-dep.sh nv-codec-headers

if [ "$BUILD_TYPE" == "static" ]; then
    ZLIB_OPTS="-DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON"
else
    ZLIB_OPTS="-DZLIB_BUILD_SHARED=ON -DZLIB_BUILD_STATIC=OFF"
fi
./build-cmake-dep.sh zlib -DZLIB_BUILD_EXAMPLES=OFF $ZLIB_OPTS
if [ ! -f "$INSTALL_PREFIX/lib/zlib.lib" ]; then
    # Fallback: find any zlib*.lib or zlib*.a or libz*.a and copy it
    # We search recursively in case it is deeply nested.
    ZLIB_CACHED_LIB=$(find "$INSTALL_PREFIX" -name "zlib*.lib" -o -name "zlib*.a" -o -name "libz*.a" | head -n 1)
    if [ -n "$ZLIB_CACHED_LIB" ]; then
        echo "[DEBUG] Found zlib lib candidate: $ZLIB_CACHED_LIB"
        cp "$ZLIB_CACHED_LIB" "$INSTALL_PREFIX/lib/zlib.lib"
    else
        echo "Error: zlib library not found in $INSTALL_PREFIX"
    fi
    echo "[DEBUG] Full recursive listing of $INSTALL_PREFIX:"
    ls -R "$INSTALL_PREFIX"
    echo "[DEBUG] Listing $INSTALL_PREFIX/lib after zlib build:"
    ls -la "$INSTALL_PREFIX/lib"
fi
add_ffargs "--enable-zlib"

if [ -n "$ENABLE_LIBFREETYPE" ]; then
    ./build-cmake-dep.sh freetype
    add_ffargs "--enable-libfreetype"
fi

if [ -n "$ENABLE_LIBHARFBUZZ" ]; then
    ./build-cmake-dep.sh harfbuzz -DHB_HAVE_FREETYPE=ON
    add_ffargs "--enable-libharfbuzz"
fi

if [ -n "$ENABLE_LIBASS" ]; then
    ./build-libass.sh

    # Rename/copy static libs for MSVC
    if [ -f "$INSTALL_PREFIX/lib/libfribidi.a" ]; then
            cp "$INSTALL_PREFIX/lib/libfribidi.a" "$INSTALL_PREFIX/lib/fribidi.lib"
    fi
    if [ -f "$INSTALL_PREFIX/lib/libass.a" ]; then
            cp "$INSTALL_PREFIX/lib/libass.a" "$INSTALL_PREFIX/lib/ass.lib"
            cp "$INSTALL_PREFIX/lib/libass.a" "$INSTALL_PREFIX/lib/libass.lib"
    fi

    add_ffargs "--enable-libass"
fi



if [ -n "$ENABLE_SDL" ]; then
    ./build-cmake-dep.sh SDL -DSDL_LIBC=ON -DCMAKE_SHARED_LINKER_FLAGS="/defaultlib:libcmt.lib /defaultlib:libvcruntime.lib /defaultlib:libucrt.lib"
    add_ffargs "--enable-sdl"
fi

if [ -n "$ENABLE_LIBJXL" ]; then

    if [ "$BUILD_TYPE" == "shared" ]; then
        JPEGXL_STATIC=OFF
    else
        JPEGXL_STATIC=ON
    fi

    apply-patch libjxl libjxl.patch
    ./build-cmake-dep.sh openexr -DOPENEXR_INSTALL_TOOLS=OFF -DOPENEXR_BUILD_TOOLS=OFF -DBUILD_TESTING=OFF -DOPENEXR_IS_SUBPROJECT=ON
    ./build-cmake-dep.sh libjxl -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_JNI=OFF -DJPEGXL_BUNDLE_LIBPNG=OFF -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF -DJPEGXL_STATIC=$JPEGXL_STATIC
    add_ffargs "--enable-libjxl"

fi

if [ -n "$ENABLE_LIBVPX" ]; then
    case $BUILD_ARCH in
    amd64) libvpx_target=x86_64-win64-vs17 ;;
    x86) libvpx_target=x86-win32-vs17 ;;
    arm) libvpx_target=armv7-win32-vs17 ;;
    arm64) libvpx_target=arm64-win64-vs17 ;;
    esac

    LIBVPX_ARGS="--enable-static-msvcrt"
    apply-patch libvpx libvpx.patch
    if [[ "$BUILD_ARCH" == "arm" || "$BUILD_ARCH" == "arm64" ]]; then
        VPX_AS_FLAGS="--as=auto"
        VPX_AS_VAL=""
    else
        VPX_AS_FLAGS="--as=yasm"
        VPX_AS_VAL="yasm"
    fi
    env CFLAGS="" AS="$VPX_AS_VAL" AR=lib ARFLAGS= CC=cl CXX=cl LD=link STRIP=false target= ./build-make-dep.sh libvpx --target=$libvpx_target $VPX_AS_FLAGS --disable-optimizations --disable-dependency-tracking --disable-runtime-cpu-detect --disable-thumb --disable-neon --enable-external-build --disable-unit-tests --disable-decode-perf-tests --disable-encode-perf-tests --disable-tools --disable-examples $LIBVPX_ARGS
    
    # Fix vpx.lib missing for shared/static builds
    if [ -f "$INSTALL_PREFIX/lib/vpxmt.lib" ]; then
        cp "$INSTALL_PREFIX/lib/vpxmt.lib" "$INSTALL_PREFIX/lib/vpx.lib"
    elif [ -f "$INSTALL_PREFIX/lib/vpxmd.lib" ]; then
        cp "$INSTALL_PREFIX/lib/vpxmd.lib" "$INSTALL_PREFIX/lib/vpx.lib"
    elif [ -f "$INSTALL_PREFIX/lib/vpx.dll.lib" ]; then
        cp "$INSTALL_PREFIX/lib/vpx.dll.lib" "$INSTALL_PREFIX/lib/vpx.lib"
    fi

    add_ffargs "--enable-libvpx"
fi

if [ -n "$ENABLE_LIBWEBP" ]; then
    ./build-cmake-dep.sh libwebp -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF
    add_ffargs "--enable-libwebp"
fi

if [ "$BUILD_LICENSE" == "gpl" ]; then

    apply-patch x265_git x265_git-${BUILD_TYPE}.patch

    if [ "$BUILD_TYPE" == "static" ]; then
        X265_ARGS="-DSTATIC_LINK_CRT=ON"
        ENABLE_SHARED=OFF
    else
        X265_ARGS="-DSTATIC_LINK_CRT=OFF"
        ENABLE_SHARED=ON
    fi

    if [ "$BUILD_ARCH" == arm ]; then
        apply-patch x265_git x265_git-arm.patch
    fi
    if [ "$BUILD_ARCH" == arm64 ]; then
        apply-patch x265_git x265_git-arm64-msvc.patch
    fi
    apply-patch x265_git x265_git-version.patch

    case $BUILD_ARCH in
        amd64) CMAKE_ARCH=AMD64 ;;
        x86)   CMAKE_ARCH=x86 ;;
        arm64) CMAKE_ARCH=ARM64 ;;
        arm)   CMAKE_ARCH=ARM ;;
    esac

    git -C x265_git fetch --tags
    X265_VER=$(git -C x265_git describe --abbrev=0 --tags 2>/dev/null || echo "0.0")
    ./build-cmake-dep.sh x265_git/source -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=$CMAKE_ARCH -DX265_LATEST_TAG=$X265_VER -DENABLE_SHARED=$ENABLE_SHARED -DENABLE_CLI=OFF $X265_ARGS
    add_ffargs "--enable-libx265"

    if [ "$BUILD_TYPE" == "shared" ]; then
        apply-patch x264 x264-${BUILD_TYPE}.patch
    fi
    if [[ "$BUILD_ARCH" =~ arm ]]; then
        X264_ARGS="--disable-asm"
    fi

    INSTALL_TARGET=install-lib-${BUILD_TYPE} ./build-make-dep.sh x264 --enable-${BUILD_TYPE} $X264_ARGS
    add_ffargs "--enable-libx264"

fi

./build-ffmpeg.sh FFmpeg $FF_ARGS
./reprefix.sh

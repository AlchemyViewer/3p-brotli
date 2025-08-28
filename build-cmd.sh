#!/usr/bin/env bash

cd "$(dirname "$0")"

top="$(pwd)"
stage="$(pwd)/stage"

mkdir -p $stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd apply_patch
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

BROTLI_SOURCE_DIR="brotli"

# Create the staging folders
mkdir -p "$stage/lib"/{debug,release}
mkdir -p "$stage/include/brotli"
mkdir -p "$stage/LICENSES"

echo "1.1.0" > "${stage}/VERSION.txt"

pushd "$BROTLI_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            for arch in sse avx2 arm64 ; do
                platform_target="x64"
                if [[ "$arch" == "arm64" ]]; then
                    platform_target="ARM64"
                fi

                mkdir -p "build_debug_$arch"
                pushd "build_debug_$arch"
                    opts="$(replace_switch /Zi /Z7 $LL_BUILD_DEBUG)"
                    if [[ "$arch" == "avx2" ]]; then
                        opts="$(replace_switch /arch:SSE4.2 /arch:AVX2 $opts)"
                    elif [[ "$arch" == "arm64" ]]; then
                        opts="$(remove_switch /arch:SSE4.2 $opts)"
                    fi
                    plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                    cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$platform_target" -DBUILD_SHARED_LIBS=FALSE \
                                -DCMAKE_CONFIGURATION_TYPES="Debug" \
                                -DCMAKE_BUILD_TYPE="Debug" \
                                -DCMAKE_C_FLAGS="$plainopts" \
                                -DCMAKE_CXX_FLAGS="$opts" \
                                -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="Embedded" \
                                -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")" \
                                -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/$arch/debug")"
                
                    cmake --build . --config Debug --clean-first --target install
                popd

                mkdir -p "build_release_$arch"
                pushd "build_release_$arch"
                    opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
                    if [[ "$arch" == "avx2" ]]; then
                        opts="$(replace_switch /arch:SSE4.2 /arch:AVX2 $opts)"
                    elif [[ "$arch" == "arm64" ]]; then
                        opts="$(remove_switch /arch:SSE4.2 $opts)"
                    fi
                    plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                    cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$platform_target" -DBUILD_SHARED_LIBS=FALSE \
                                -DCMAKE_CONFIGURATION_TYPES="Release" \
                                -DCMAKE_BUILD_TYPE="Release" \
                                -DCMAKE_C_FLAGS="$plainopts" \
                                -DCMAKE_CXX_FLAGS="$opts" \
                                -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="Embedded" \
                                -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")" \
                                -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/$arch/release")"
                
                    cmake --build . --config Release --clean-first --target install
                popd
            done
        ;;
        # ------------------------- darwin, darwin64 -------------------------
        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                cc_opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $cc_opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -GXcode -DBUILD_SHARED_LIBS:BOOL=OFF \
                        -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                        -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                        -DCMAKE_OSX_ARCHITECTURES="$arch" \
                        -DCMAKE_INSTALL_PREFIX=$stage \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/$arch/release"

                    cmake --build . --config Release --clean-first --target install

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release
                    fi
                popd
            done

            lipo -create -output "$stage/lib/release/libbrotlienc.a" "$stage/lib/x86_64/release/libbrotlienc.a" "$stage/lib/arm64/release/libbrotlienc.a"
            lipo -create -output "$stage/lib/release/libbrotlidec.a" "$stage/lib/x86_64/release/libbrotlidec.a" "$stage/lib/arm64/release/libbrotlidec.a"
            lipo -create -output "$stage/lib/release/libbrotlicommon.a" "$stage/lib/x86_64/release/libbrotlicommon.a" "$stage/lib/arm64/release/libbrotlicommon.a"
        ;;
        linux*)
            for arch in sse avx2 ; do
                # Default target per autobuild build --address-size
                opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
                if [[ "$arch" == "avx2" ]]; then
                    opts="$(replace_switch -march=x86-64-v2 -march=x86-64-v3 $opts)"
                fi
                plainopts="$(remove_cxxstd $opts)"

                # Release
                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$plainopts" \
                    CXXFLAGS="$opts" \
                        cmake ../ -G"Ninja" -DBUILD_SHARED_LIBS:BOOL=OFF \
                            -DCMAKE_BUILD_TYPE=Release \
                            -DCMAKE_C_FLAGS="$plainopts" \
                            -DCMAKE_CXX_FLAGS="$opts" \
                            -DCMAKE_INSTALL_PREFIX=$stage \
                            -DCMAKE_INSTALL_LIBDIR="$stage/lib/$arch/release"


                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release
                popd
            done
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/brotli.txt"
popd

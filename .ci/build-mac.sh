#!/bin/sh -ex

# Gather explicit version number and number of commits

COMM_TAG=$(awk '/version{.*}/ { printf("%d.%d.%d", $5, $6, $7) }' rpcs3/rpcs3_version.cpp)
COMM_COUNT=$(git rev-list --count HEAD)
COMM_HASH=$(git rev-parse --short=8 HEAD)

AVVER="${COMM_TAG}-${COMM_COUNT}"
export LVER="${COMM_TAG}-${COMM_COUNT}-${COMM_HASH}"

echo "AVVER=$AVVER" >> .ci/ci-vars.env

# Homebrew

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

brew update

# Fallback nếu biến không tồn tại

brew install -f --overwrite --quiet ccache   

if [ "$AARCH64" -eq 1 ]; then
    brew install -f --overwrite --quiet \
        googletest \
        opencv@4 \
        sdl3 \
        vulkan-headers \
        vulkan-loader \
        molten-vk

    brew unlink --quiet ffmpeg fmt qtbase qtsvg qtdeclarative protobuf || true
else
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"


arch -x86_64 /usr/local/bin/brew install -f --overwrite --quiet \
    python@3.14 \
    opencv@4 \
    "llvm@$LLVM_COMPILER_VER" \
    sdl3 \
    vulkan-headers \
    vulkan-loader \
    molten-vk

arch -x86_64 /usr/local/bin/brew unlink --quiet \
    ffmpeg qtbase qtsvg qtdeclarative protobuf || true
fi


if [ "$AARCH64" -eq 1 ]; then
BREW_PATH="$(brew --prefix)"
export BREW_BIN="/opt/homebrew/bin"
export BREW_SBIN="/opt/homebrew/sbin"
else
BREW_PATH="$("/usr/local/bin/brew" --prefix)"
export BREW_BIN="/usr/local/bin"
export BREW_SBIN="/usr/local/sbin"
fi

WORKDIR="$(pwd)"
export WORKDIR

# LLVM 19.1.0
if [ ! -d /tmp/llvm19 ]; then
    echo "Downloading LLVM 19.1.0..."

    curl -L \
    "https://drive.usercontent.google.com/download?id=1VqGI4QH4p2j0Ldg_2zDvvF_tu6qOHzqA&export=download&confirm=t" \
    -o /tmp/llvm19.tar.gz

    rm -rf /tmp/llvm19
    mkdir -p /tmp/llvm19

    tar -xzf /tmp/llvm19.tar.gz -C /tmp/llvm19
fi

LLVM_ROOT="$(find /tmp/llvm19 -maxdepth 1 -type d -name 'LLVM-*' | head -1)"

echo "LLVM_ROOT=$LLVM_ROOT"

"$LLVM_ROOT/bin/clang" --version
"$LLVM_ROOT/bin/clang++" --version

rm -f "$LLVM_ROOT/lib/libc++.1.0.dylib"
rm -f "$LLVM_ROOT/lib/libc++abi.dylib"
rm -f "$LLVM_ROOT/lib/libunwind.1.dylib"

export LLVM_DIR="$LLVM_ROOT"

export CC="$LLVM_ROOT/bin/clang"
export CXX="$LLVM_ROOT/bin/clang++"

export PATH="$LLVM_ROOT/bin:$PATH"


mkdir -p "$CCACHE_DIR"

echo "Downloading prebuilt Qt 6.5.8..."

mkdir -p /tmp

curl -L \
    "https://drive.usercontent.google.com/download?id=1tiGT8NU3eUkfU956kkQilYwuK2kUCnC3&export=download&confirm=t&uuid=3ad22766-0f54-48b6-bfd2-de26be6d9383" \
    -o /tmp/qt-6.5.8-arm64.tar.gz

rm -rf /tmp/qt65
tar -xzf /tmp/qt-6.5.8-arm64.tar.gz -C /tmp

export CMAKE_PREFIX_PATH=/tmp/qt65

export Qt6_DIR=/tmp/qt65/lib/cmake/Qt6
export Qt6CoreTools_DIR=/tmp/qt65/lib/cmake/Qt6CoreTools
export Qt6WidgetsTools_DIR=/tmp/qt65/lib/cmake/Qt6WidgetsTools
export Qt6DBusTools_DIR=/tmp/qt65/lib/cmake/Qt6DBusTools

echo "Qt6_DIR=$Qt6_DIR"
echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"

find /tmp/qt65/lib/cmake -maxdepth 1 -type d | sort

export SDL3_DIR="$BREW_PATH/opt/sdl3/lib/cmake/SDL3"

export VULKAN_SDK="$BREW_PATH/opt/molten-vk"

ln -sf \
    "$BREW_PATH/opt/vulkan-loader/lib/libvulkan.dylib" \
    "$VULKAN_SDK/lib/libvulkan.dylib"

git submodule -q update --init --depth=1 --jobs=8 \
$(awk '/path/ && !/llvm/ && !/opencv/ && !/SDL/ && !/feralinteractive/ { print $3 }' .gitmodules)

rm -rf build
mkdir -p build
cd build

cmake .. \
-DCMAKE_PREFIX_PATH=/tmp/qt65 \
-DQt6_DIR="$Qt6_DIR" \
-DQt6CoreTools_DIR="$Qt6CoreTools_DIR" \
-DQt6WidgetsTools_DIR="$Qt6WidgetsTools_DIR" \
-DQt6DBusTools_DIR="$Qt6DBusTools_DIR" \
-DSDL3_DIR="$SDL3_DIR" \
-DBUILD_RPCS3_TESTS="${RUN_UNIT_TESTS}" \
-DRUN_RPCS3_TESTS="${RUN_UNIT_TESTS}" \
-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
-DCMAKE_OSX_ARCHITECTURES=arm64 \
-DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" \
-DMACOSX_BUNDLE_SHORT_VERSION_STRING="${COMM_TAG}" \
-DMACOSX_BUNDLE_BUNDLE_VERSION="${COMM_COUNT}" \
-DSTATIC_LINK_LLVM=ON \
-DUSE_SDL=ON \
-DUSE_DISCORD_RPC=ON \
-DUSE_AUDIOUNIT=ON \
-DUSE_SYSTEM_FFMPEG=OFF \
-DUSE_NATIVE_INSTRUCTIONS=OFF \
-DUSE_PRECOMPILED_HEADERS=OFF \
-DUSE_SYSTEM_MVK=ON \
-DUSE_SYSTEM_SDL=ON \
-DUSE_SYSTEM_OPENCV=ON \
-DCMAKE_CXX_FLAGS="-Wno-error=return-type" \
-G Ninja


ninja
build_status=$?

cd ..

if [ "$build_status" -eq 0 ]; then
    .ci/deploy-mac.sh
fi

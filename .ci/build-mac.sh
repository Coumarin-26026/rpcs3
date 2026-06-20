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

# Install dependencies

brew install -f --overwrite --quiet 
ccache 
"llvm@$LLVM_COMPILER_VER"

brew link -f --overwrite --quiet 
"llvm@$LLVM_COMPILER_VER"

brew install -f --overwrite --quiet 
googletest 
opencv@4 
sdl3 
vulkan-headers 
vulkan-loader 
molten-vk

brew unlink --quiet 
ffmpeg 
fmt 
qtbase 
qtsvg 
qtdeclarative 
protobuf || true

export CC=clang
export CXX=clang++

export BREW_PATH
BREW_PATH="$(brew --prefix)"

export BREW_BIN="$BREW_PATH/bin"
export BREW_SBIN="$BREW_PATH/sbin"

export WORKDIR
WORKDIR="$(pwd)"

# ccache

if [ ! -d "$CCACHE_DIR" ]; then
mkdir -p "$CCACHE_DIR"
fi

# Build Qt from source

export DEPS_DIR="$WORKDIR/deps"

chmod +x .ci/build-dependencies-universal.sh

if [ ! -f "$DEPS_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]; then
echo "Qt not found. Building dependencies..."

```
export BUILD_FFMPEG=0

.ci/build-dependencies-universal.sh "$DEPS_DIR"
```

fi

# Toolchain

export Qt6_DIR="$DEPS_DIR/lib/cmake/Qt6"
export CMAKE_PREFIX_PATH="$DEPS_DIR"

export SDL3_DIR="$BREW_PATH/opt/sdl3/lib/cmake/SDL3"

export PATH="$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/bin:$PATH"

export LDFLAGS="-L$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/lib/c++ 
-L$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/lib/unwind 
-lunwind"

# Vulkan

export VULKAN_SDK="$BREW_PATH/opt/molten-vk"

if [ ! -e "$VULKAN_SDK/lib/libvulkan.dylib" ]; then
ln -sf 
"$BREW_PATH/opt/vulkan-loader/lib/libvulkan.dylib" 
"$VULKAN_SDK/lib/libvulkan.dylib"
fi

# LLVM

export LLVM_DIR="$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER"

# Submodules

git submodule -q update 
--init 
--depth=1 
--jobs=8 
$(awk '/path/ && !/llvm/ && !/opencv/ && !/SDL/ && !/feralinteractive/ { print $3 }' .gitmodules)

# Build

rm -rf build
mkdir build
cd build

cmake .. 
-DCMAKE_PREFIX_PATH="$DEPS_DIR" 
-DBUILD_RPCS3_TESTS="${RUN_UNIT_TESTS}" 
-DRUN_RPCS3_TESTS="${RUN_UNIT_TESTS}" 
-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 
-DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" 
-DMACOSX_BUNDLE_SHORT_VERSION_STRING="${COMM_TAG}" 
-DMACOSX_BUNDLE_BUNDLE_VERSION="${COMM_COUNT}" 
-DSTATIC_LINK_LLVM=ON 
-DUSE_SDL=ON 
-DUSE_DISCORD_RPC=ON 
-DUSE_AUDIOUNIT=ON 
-DUSE_SYSTEM_FFMPEG=OFF 
-DUSE_NATIVE_INSTRUCTIONS=OFF 
-DUSE_PRECOMPILED_HEADERS=OFF 
-DUSE_SYSTEM_MVK=ON 
-DUSE_SYSTEM_SDL=ON 
-DUSE_SYSTEM_OPENCV=ON 
-G Ninja

ninja -j$(sysctl -n hw.logicalcpu)

build_status=$?

cd ..

if [ "$build_status" -eq 0 ]; then
.ci/deploy-mac.sh
fi

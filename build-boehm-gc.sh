#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds Boehm GC from sources. The version is
# pinned at Boehm-GC 7.2k to avoid the libatomics. Many
# C++ compilers claim to be C++11 but lack all the features.

GC_TAR=gc-7.2k.tar.gz
GC_DIR=gc-7.2
PKG_NAME=boehm-gc

# Avoid shellcheck.net warning
CURR_DIR="$PWD"

# Sets the number of make jobs if not set in environment
: "${INSTX_JOBS:=4}"

###############################################################################

# Get the environment as needed. We can't export it because it includes arrays.
if ! source ./build-environ.sh
then
    echo "Failed to set environment"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

CA_ZOO="$HOME/.cacert/cacert.pem"
if [[ ! -f "$CA_ZOO" ]]; then
    echo "Boehm GC requires several CA roots. Please run build-cacert.sh."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ -e "$INSTX_CACHE/$PKG_NAME" ]]; then
    # Already installed, return success
    echo ""
    echo "$PKG_NAME is already installed."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
fi

# The password should die when this subshell goes out of scope
if [[ -z "$SUDO_PASSWORD" ]]; then
    source ./build-password.sh
fi

###############################################################################

echo
echo "********** Boehm GC **********"
echo

# https://github.com/ivmai/bdwgc/releases/download/v7.2k/gc-7.2k.tar.gz
"$WGET" --ca-certificate="$CA_ZOO" "https://github.com/ivmai/bdwgc/releases/download/v7.2k/$GC_TAR" -O "$GC_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download Boehm GC"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$GC_DIR" &>/dev/null
gzip -d < "$GC_TAR" | tar xf -
cd "$GC_DIR"

# Fix sys_lib_dlsearch_path_spec and keep the file time in the past
../fix-config.sh

CONFIG_OPTS=()
CONFIG_OPTS+=("--prefix=$INSTX_PREFIX")
CONFIG_OPTS+=("--libdir=$INSTX_LIBDIR")
CONFIG_OPTS+=("--enable-shared")

# Awful Solaris 64-bit hack. Rewrite some values
if [[ "$IS_SOLARIS" -eq "1" ]]; then
    # Autotools uses the i386-pc-solaris2.11, which results in 32-bit binaries
    if [[ "$IS_X86_64" -eq "1" ]]; then
        # Fix Autotools mis-detection on Solaris
        CONFIG_OPTS+=("--build=x86_64-pc-solaris2.11")
        CONFIG_OPTS+=("--host=x86_64-pc-solaris2.11")
    fi
fi

    PKG_CONFIG_PATH="${BUILD_PKGCONFIG[*]}" \
    CPPFLAGS="${BUILD_CPPFLAGS[*]}" \
    CFLAGS="${BUILD_CFLAGS[*]}" \
    CXXFLAGS="${BUILD_CXXFLAGS[*]}" \
    LDFLAGS="${BUILD_LDFLAGS[*]}" \
    LIBS="${BUILD_LIBS[*]}" \
./configure "${CONFIG_OPTS[@]}"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure Boehm GC"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("-j" "$INSTX_JOBS")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build Boehm GC"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("check")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to test Boehm GC"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("install")
if [[ ! (-z "$SUDO_PASSWORD") ]]; then
    echo "$SUDO_PASSWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
fi

cd "$CURR_DIR"

# Set package status to installed. Delete the file to rebuild the package.
touch "$INSTX_CACHE/$PKG_NAME"

###############################################################################

# Set to false to retain artifacts
if true; then

    ARTIFACTS=("$GC_TAR" "$GC_DIR")
    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done

    # ./build-boehmgc.sh 2>&1 | tee build-boehmgc.log
    if [[ -e build-boehmgc.log ]]; then
        rm -f build-boehmgc.log
    fi
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0

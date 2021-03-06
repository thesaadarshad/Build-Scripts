#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds Unbound from sources.

UNBOUND_TAR=unbound-1.7.3.tar.gz
UNBOUND_DIR=unbound-1.7.3
PKG_NAME=unbound

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

if [[ -e "$INSTX_CACHE/$PKG_NAME" ]]; then
    # Already installed, return success
    echo ""
    echo "$PKG_NAME is already installed."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
fi

# Get a sudo password as needed. The password should die when this
# subshell goes out of scope.
if [[ -z "$SUDO_PASSWORD" ]]; then
    source ./build-password.sh
fi

###############################################################################

echo
echo "********** Unbound **********"
echo

"$WGET" --ca-certificate="$IDENTRUST_ROOT" "https://unbound.net/downloads/$UNBOUND_TAR" -O "$UNBOUND_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download Unbound"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$UNBOUND_DIR" &>/dev/null
gzip -d < "$UNBOUND_TAR" | tar xf -
cd "$UNBOUND_DIR"

cp configure configure.bu

# https://nlnetlabs.nl/bugs-script/show_bug.cgi?id=4131
"$WGET" --ca-certificate="$IDENTRUST_ROOT" www.nlnetlabs.nl/svn/unbound/trunk/configure -O configure
touch -t 197001010000 configure

if [[ "$?" -ne "0" ]]; then
    echo "Failed to update configure file"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

# Fix sys_lib_dlsearch_path_spec and keep the file time in the past
../fix-config.sh

    PKG_CONFIG_PATH="${BUILD_PKGCONFIG[*]}" \
    CPPFLAGS="${BUILD_CPPFLAGS[*]}" \
    CFLAGS="${BUILD_CFLAGS[*]}" \
    CXXFLAGS="${BUILD_CXXFLAGS[*]}" \
    LDFLAGS="${BUILD_LDFLAGS[*]}" \
    LIBS="${BUILD_LIBS[*]}" \
./configure --enable-shared --prefix="$INSTX_PREFIX" --libdir="$INSTX_LIBDIR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure Unbound"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("-j" "$INSTX_JOBS")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build Unbound"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("check" "V=1")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to test Unbound"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -f root.key 2>/dev/null
UNBOUND_ANCHOR_PROG=$(find "$PWD" -name unbound-anchor | head -n 1)
if [[ -z "$UNBOUND_ANCHOR_PROG" ]]; then
    echo "Failed to locate unbound-anchor tool"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

echo "Creating root key from data.iana.org"
touch root.key

#if ! "$UNBOUND_ANCHOR_PROG" -a ./root.key -u data.iana.org
#then
#    echo "Failed to create root.key"
#    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
#fi

# Can't check error codes because they are ambiguous.
# https://www.nlnetlabs.nl/bugs-script/show_bug.cgi?id=4134
"$UNBOUND_ANCHOR_PROG" -a ./root.key -u data.iana.org

# Use https://www.icann.org/dns-resolvers-checking-current-trust-anchors
COUNT=$(grep -i -c -E 'id = 20326|id = 19036' root.key)
if [[ "$COUNT" -ne "2" ]]; then
    echo "Failed to create root.key"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi
COUNT=$(grep -i -c 'state=2 \[  VALID  \]' root.key)
if [[ "$COUNT" -ne "2" ]]; then
    echo "Failed to create root.key"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("install")
if [[ ! (-z "$SUDO_PASSWORD") ]]; then
    echo "$SUDO_PASSWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
    echo "$SUDO_PASSWORD" | sudo -S cp "root.key" "$INSTX_PREFIX/etc/unbound/root.key"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
    cp "root.key" "$INSTX_PREFIX/etc/unbound/root.key"
fi

cd "$CURR_DIR"

# Set package status to installed. Delete the file to rebuild the package.
touch "$INSTX_CACHE/$PKG_NAME"

###############################################################################

echo ""
echo "*****************************************************************************"
echo "You should create a cron job that runs unbound-anchor on a"
echo "regular basis to update $INSTX_PREFIX/etc/unbound/root.key"
echo "*****************************************************************************"

###############################################################################

# Set to false to retain artifacts
if true; then

    ARTIFACTS=("$UNBOUND_TAR" "$UNBOUND_DIR")
    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done

    # ./build-unbound.sh 2>&1 | tee build-unbound.log
    if [[ -e build-unbound.log ]]; then
        rm -f build-unbound.log
    fi
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0

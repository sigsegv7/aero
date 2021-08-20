#!/bin/bash

# Copyright (C) 2021 The Aero Project Developers.
#
# This file is part of The Aero Project.
#
# Aero is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Aero is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Aero. If not, see <https://www.gnu.org/licenses/>.

SPATH=$(dirname $(readlink -f "$0"))

AERO_PATH=$(realpath $SPATH/..)
AERO_USERLAND=$AERO_PATH/userland
AERO_SYSROOT=$AERO_PATH/sysroot/aero
AERO_SYSROOT_BUILD=$AERO_PATH/sysroot/build
AERO_BUNDLED=$AERO_PATH/bundled

AERO_CROSS=$AERO_PATH/sysroot/cross
AERO_TRIPLE=x86_64-aero

export PATH=$AERO_PATH/sysroot/bin:$AERO_CROSS/bin:$PATH

set -x -e

# This function is responsible for building and assembling the mlibc headers.
function setup_sysroot {
    meson setup --cross-file $AERO_USERLAND/cross-file.ini \
        --prefix $AERO_SYSROOT/usr \
        -Dheaders_only=true \
        -Dstatic=true \
        $AERO_SYSROOT_BUILD/mlibc $AERO_BUNDLED/mlibc
    
    pushd .
    cd $AERO_SYSROOT_BUILD/mlibc

    ninja
    ninja install

    popd
}

# This function is responsible for building and assembling the mlibc runtime objects.
function setup_mlibc {
    meson setup --cross-file $AERO_USERLAND/cross-file.ini \
        --prefix $AERO_SYSROOT/usr \
        -Dstatic=true \
        -Dheaders_only=false \
        --reconfigure \
        $AERO_SYSROOT_BUILD/mlibc $AERO_BUNDLED/mlibc

    pushd .
    cd $AERO_SYSROOT_BUILD/mlibc

    ninja
    ninja install

    popd
}

function setup_nyancat {
    pushd .

	cd $AERO_BUNDLED/nyancat/src
	make clean
	CC=$AERO_TRIPLE-gcc make
	cp nyancat $AERO_SYSROOT_BUILD
	make clean

	popd
}

# This function is responsible for building and assembling host binutils.
function setup_binutils {
    mkdir -p $AERO_SYSROOT_BUILD/binutils-gdb

    pushd .

	cd $AERO_SYSROOT_BUILD/binutils-gdb

    # --disable-werror: On recent compilers, binutils 2.26 causes implicit-fallthrough warnings, among others.
	$AERO_BUNDLED/binutils-gdb/configure \
        --target=$AERO_TRIPLE \
        --prefix="$AERO_CROSS" \
        --with-sysroot=$AERO_SYSROOT \
        --disable-werror \
        --disable-gdb

	popd

    make -C $AERO_SYSROOT_BUILD/binutils-gdb -j$(nproc)
	make -C $AERO_SYSROOT_BUILD/binutils-gdb install
}

# This function is responsible for building and assembling libgcc.
function setup_gcc {
    # Install all of the required packages required to build GCC from source. This would require admin permissions
    # so, follow the prompt for putting in your root password.
    sudo apt install bison flex libgmp3-dev libmpc-dev libmpfr-dev texinfo gcc automake make

    mkdir -p $AERO_SYSROOT_BUILD/gcc

    # The first step of compiling GCC for the Aero target is to download and extract the
    # prerequisite dependencies that GCC requires. We use the helper script `download_prerequisites`
    # to download them. The script requires to run in the root directory of GCC itself so we push the src
    # directory then run the script and pop the directory.
    pushd . 
    cd $AERO_BUNDLED/gcc 
    ./contrib/download_prerequisites
    popd

    # After we are done downloading all of the prerequisite dependencies, we can build GCC. We use the helper
    # configure command from GCC itself, which makes the build process of building GCC much simpler. The configure
    # script requires the current directory to be the build directory so, we push into the GCC build directory here.
    pushd .
    cd $AERO_SYSROOT_BUILD/gcc

    # Run the configure script and only enable C and C++ languages and set enable-threads to posix. See the documentation of the
    # configure script in bundled/gcc/configure for more information.
    $AERO_BUNDLED/gcc/configure --target=$AERO_TRIPLE \
        --prefix="$AERO_CROSS" \
        --with-sysroot=$AERO_SYSROOT \
        --enable-languages=c,c++ \
        --enable-threads=posix
    popd

    # Do the actual compilation of GCC by executing MAKE and compiling libgcc. If you run out of memory, try setting the
    # job number `-j` to an amount lower then 4.
    make -C $AERO_SYSROOT_BUILD/gcc -j$(nproc) all-gcc all-target-libgcc
    make -C $AERO_SYSROOT_BUILD/gcc install-gcc install-target-libgcc
}

function setup_all {
    setup_sysroot
    setup_binutils
    setup_gcc
    setup_mlibc
}

function setup_test {
    x86_64-aero-gcc $AERO_PATH/test.c -o $AERO_PATH/test.out
}

setup_$1

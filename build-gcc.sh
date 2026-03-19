#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
# Author: Vaisakh Murali
set -e

echo "*****************************************"
echo "* Building Bare-Metal Bleeding Edge GCC *"
echo "*****************************************"

# Declare the number of jobs to run simultaneously
JOBS=$(nproc --all)

# TODO: Add more dynamic option handling
while getopts a: flag; do
  case "${flag}" in
    a) arch=${OPTARG} ;;
    *) echo "Invalid argument passed" && exit 1 ;;
  esac
done

# TODO: Better target handling
case "${arch}" in
  "arm") TARGET="arm-none-eabi" ;;
  "armgnu") TARGET="arm-linux-gnueabi" ;;
  "arm64") TARGET="aarch64-elf" ;;
  "arm64gnu") TARGET="aarch64-linux-gnu" ;;
  "x86") TARGET="x86_64-elf" ;;
  "x86gnu") TARGET="x86_64-pc-linux-gnu" ;;
  *) echo "Unsupported architecture: ${arch}" && exit 1 ;;
esac

export WORK_DIR="$PWD"
export PREFIX="$WORK_DIR/gcc-${arch}"
export SYSROOT="$PREFIX/$TARGET"
export PATH="$PREFIX/bin:/usr/bin/core_perl:$PATH"
export OPT_FLAGS="-O2 -pipe -ffunction-sections -fdata-sections -fstack-protector-strong"

echo "Cleaning up previously cloned repos..."
rm -rf "$WORK_DIR"/{binutils,build-binutils,build-gcc-stage1,build-gcc-final,build-newlib,gcc,newlib-cygwin} "$PREFIX"/*

mkdir -p "$PREFIX"
mkdir -p "$SYSROOT"

echo "||                                                                    ||"
echo "|| Building Bare Metal Toolchain for ${arch} with ${TARGET} as target ||"
echo "||                                                                    ||"

download_resources() {
  echo "Downloading Pre-requisites"
  echo "Cloning binutils"
  git clone https://sourceware.org/git/binutils-gdb.git -b master "$WORK_DIR"/binutils --depth=1
  sed -i '/^development=/s/true/false/' "$WORK_DIR"/binutils/bfd/development.sh
  echo "Cloned binutils!"
  echo "Cloning GCC"
  git clone https://gcc.gnu.org/git/gcc.git -b master "$WORK_DIR"/gcc --depth=1
  echo "Cloning Newlib"
  git clone https://sourceware.org/git/newlib-cygwin.git -b master "$WORK_DIR"/newlib-cygwin --depth=1
  echo "Downloaded prerequisites!"
}

build_binutils() {
  echo "Building Binutils"
  mkdir -p "$WORK_DIR"/build-binutils
  pushd "$WORK_DIR"/gcc || exit 1
  export trim_ver="$(cat gcc/BASE-VER | cut -c 1-2)"
  popd || exit 1
  pushd "$WORK_DIR"/build-binutils || exit 1
  env CFLAGS="$OPT_FLAGS" CXXFLAGS="$OPT_FLAGS" \
  "$WORK_DIR"/binutils/configure --target="$TARGET" \
    --disable-docs \
    --disable-gdb \
    --disable-nls \
    --disable-werror \
    --disable-multilib \
    --prefix="$PREFIX" \
    --with-pkgversion="Gf Binutils v${trim_ver}" \
    --with-sysroot="$SYSROOT"
  make -j"$JOBS"
  make install -j"$JOBS"
  popd || exit 1
  echo "Built Binutils, proceeding to next step...."
}

build_gcc_stage1() {
  echo "Building GCC Stage 1"
  pushd "$WORK_DIR"/gcc || exit 1
  ./contrib/download_prerequisites
  echo "Gf's C Compiler, GNU-compatible" > gcc/DEV-PHASE
  cat gcc/DATESTAMP > /tmp/gcc_date
  echo "$(git rev-parse --short HEAD)" > /tmp/gcc_hash
  echo "$(git log --pretty='format:%s' | head -n1)" > /tmp/gcc_commit
  popd || exit 1
  mkdir -p "$WORK_DIR"/build-gcc-stage1
  pushd "$WORK_DIR"/build-gcc-stage1 || exit 1
  env CFLAGS="$OPT_FLAGS" CXXFLAGS="$OPT_FLAGS" \
  "$WORK_DIR"/gcc/configure --target="$TARGET" \
    --disable-decimal-float \
    --disable-docs \
    --disable-gcov \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --enable-languages=c \
    --prefix="$PREFIX" \
    --with-gnu-as \
    --with-gnu-ld \
    --with-newlib \
    --without-headers \
    --with-sysroot="$SYSROOT"
  make all-gcc -j"$JOBS"
  make all-target-libgcc -j"$JOBS"
  make install-gcc -j"$JOBS"
  make install-target-libgcc -j"$JOBS"
  popd || exit 1
  echo "Built GCC Stage 1, proceeding to next step...."
}

build_newlib() {
  echo "Building Newlib"
  mkdir -p "$WORK_DIR"/build-newlib
  pushd "$WORK_DIR"/build-newlib || exit 1
  env CFLAGS_FOR_TARGET="$OPT_FLAGS" \
  "$WORK_DIR"/newlib-cygwin/configure --target="$TARGET" \
    --disable-docs \
    --disable-multilib \
    --disable-nls \
    --prefix="$PREFIX"
  make -j"$JOBS"
  make install -j"$JOBS"
  popd || exit 1
  echo "Built Newlib, proceeding to next step...."
}

build_gcc() {
  echo "Building GCC"
  mkdir -p "$WORK_DIR"/build-gcc-final
  pushd "$WORK_DIR"/build-gcc-final || exit 1
  env CFLAGS="$OPT_FLAGS" CXXFLAGS="$OPT_FLAGS" \
  "$WORK_DIR"/gcc/configure --target="$TARGET" \
    --disable-decimal-float \
    --disable-docs \
    --disable-gcov \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --enable-languages=c \
    --prefix="$PREFIX" \
    --with-gnu-as \
    --with-gnu-ld \
    --with-newlib \
    --with-sysroot="$SYSROOT"
  make -j"$JOBS"
  make install -j"$JOBS"
  popd || exit 1
  echo "Built GCC!"
}

download_resources
build_binutils
build_gcc_stage1
build_newlib
build_gcc

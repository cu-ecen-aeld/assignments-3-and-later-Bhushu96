#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo
# Updated to fully satisfy AESD Assignment 3 requirements

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -ge 1 ]; then
    OUTDIR=$1
fi

echo "Using output directory: ${OUTDIR}"
mkdir -p "${OUTDIR}"

##############################################
# Build the Linux kernel
##############################################

cd "${OUTDIR}"

if [ ! -d linux-stable ]; then
    echo "Cloning Linux kernel ${KERNEL_VERSION}"
    git clone ${KERNEL_REPO} --depth 1 --branch ${KERNEL_VERSION} linux-stable
fi

cd linux-stable
echo "Building Linux kernel"
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all

# Copy kernel Image to OUTDIR
cp arch/${ARCH}/boot/Image "${OUTDIR}/Image"

##############################################
# Create root filesystem
##############################################

cd "${OUTDIR}"

if [ -d rootfs ]; then
    sudo rm -rf rootfs
fi

mkdir -p rootfs/{bin,sbin,etc,proc,sys,usr/{bin,sbin},dev,lib,lib64,home}

##############################################
# Build and install BusyBox
##############################################

if [ ! -d busybox ]; then
    git clone git://busybox.net/busybox.git
fi

cd busybox
git checkout ${BUSYBOX_VERSION}

make distclean
make defconfig
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX="${OUTDIR}/rootfs" install

# Set BusyBox setuid root
chmod u+s "${OUTDIR}/rootfs/bin/busybox"

##############################################
# Add required shared libraries
##############################################

SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

cp -a ${SYSROOT}/lib/ld-linux-aarch64.so.1 "${OUTDIR}/rootfs/lib/"
cp -a ${SYSROOT}/lib64/libc.so.6 "${OUTDIR}/rootfs/lib64/"
cp -a ${SYSROOT}/lib64/libm.so.6 "${OUTDIR}/rootfs/lib64/"
cp -a ${SYSROOT}/lib64/libresolv.so.2 "${OUTDIR}/rootfs/lib64/"

##############################################
# Create device nodes
##############################################

sudo mknod -m 666 "${OUTDIR}/rootfs/dev/null" c 1 3
sudo mknod -m 600 "${OUTDIR}/rootfs/dev/console" c 5 1

##############################################
# Build writer application
##############################################

cd "${FINDER_APP_DIR}"
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

##############################################
# Copy application and scripts to rootfs
##############################################

cp writer "${OUTDIR}/rootfs/home/"
cp finder.sh "${OUTDIR}/rootfs/home/"
cp finder-test.sh "${OUTDIR}/rootfs/home/"
cp conf/username.txt "${OUTDIR}/rootfs/home/"
cp conf/assignment.txt "${OUTDIR}/rootfs/home/"
cp autorun-qemu.sh "${OUTDIR}/rootfs/home/"

##############################################
# Fix ownership
##############################################

sudo chown -R root:root "${OUTDIR}/rootfs"

##############################################
# Create initramfs
##############################################

cd "${OUTDIR}/rootfs"
find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"

echo "Build complete!"
echo "Kernel Image: ${OUTDIR}/Image"
echo "Initramfs:    ${OUTDIR}/initramfs.cpio.gz"

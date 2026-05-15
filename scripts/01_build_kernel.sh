#!/usr/bin/env bash
# scripts/01_build_kernel.sh
set -euo pipefail

KERNEL_TAG="${KERNEL_TAG:-v6.12}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
KERNEL_SRC="$WORKSPACE_ROOT/kernel/linux"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; NC='\033[0m'

echo -e "${CYAN}[1/5] Clonando kernel ${KERNEL_TAG}...${NC}"
if [ ! -d "$KERNEL_SRC" ]; then
  git clone --depth 1 --branch "$KERNEL_TAG" https://github.com/torvalds/linux.git "$KERNEL_SRC"
else
  echo -e "${YELLOW}  → Fuentes ya presentes, omitiendo clone.${NC}"
fi

cd "$KERNEL_SRC"
echo -e "${CYAN}[2/5] Guardando hash del commit vulnerable...${NC}"
VULN_HASH=$(git rev-parse HEAD)
mkdir -p "$WORKSPACE_ROOT/kernel"
echo "$VULN_HASH" > "$WORKSPACE_ROOT/kernel/vuln_commit.txt"

echo -e "${CYAN}[3/5] Configurando el kernel (tiny + algif_aead)...${NC}"
make tinyconfig

# Habilitar opciones críticas de bajo nivel para QEMU y evitar el Kernel Panic
scripts/config --enable 64BIT
scripts/config --enable SERIAL_8250
scripts/config --enable SERIAL_8250_CONSOLE
scripts/config --enable TTY
scripts/config --enable BLK_DEV_INITRD
scripts/config --enable INITRAMFS_SOURCE
scripts/config --enable TMPFS
scripts/config --enable NET
scripts/config --enable UNIX
scripts/config --enable INET

# Componentes de la superficie expuesta (algif_aead)
scripts/config --enable CRYPTO
scripts/config --enable CRYPTO_USER_API
scripts/config --enable CRYPTO_USER_API_AEAD
scripts/config --enable CRYPTO_USER_API_SKCIPHER
scripts/config --enable CRYPTO_AUTHENCESN
scripts/config --enable CRYPTO_AES
scripts/config --enable CRYPTO_CBC
scripts/config --enable CRYPTO_HMAC
scripts/config --enable CRYPTO_SHA256
scripts/config --enable MULTIUSER
scripts/config --enable PRINTK
scripts/config --enable EARLY_PRINTK
scripts/config --enable PROC_FS
scripts/config --enable SYSFS
scripts/config --enable DEVTMPFS
scripts/config --enable DEVTMPFS_MOUNT
scripts/config --enable RD_GZIP
scripts/config --enable BINFMT_ELF
scripts/config --enable BINFMT_SCRIPT

make olddefconfig

echo -e "${CYAN}[4/5] Compilando bzImage...${NC}"
make -j"$JOBS" bzImage 2>&1 | tail -5

mkdir -p "$BUILD_DIR"
cp arch/x86/boot/bzImage "$BUILD_DIR/bzImage_vuln"
echo -e "${GREEN}[5/5] ✓ Kernel listo en kernel/build/bzImage_vuln${NC}"
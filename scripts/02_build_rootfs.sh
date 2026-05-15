#!/usr/bin/env bash
# scripts/02_build_rootfs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}[1/6] Clonando BusyBox...${NC}"
if [ ! -d "$BUSYBOX_SRC" ]; then
  git clone --depth 1 https://git.busybox.net/busybox "$BUSYBOX_SRC"
fi

cd "$BUSYBOX_SRC"
echo -e "${CYAN}[2/6] Configurando BusyBox...${NC}"
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
grep -q "CONFIG_STATIC=y" .config || echo "CONFIG_STATIC=y" >> .config
sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config   

echo -e "${CYAN}[3/6] Compilando BusyBox...${NC}"
make -j"$JOBS" 2>&1 | tail -3

echo -e "${CYAN}[4/6] Instalando BusyBox...${NC}"
mkdir -p "$INITRAMFS_DIR"
make CONFIG_PREFIX="$INITRAMFS_DIR" install

mkdir -p "$INITRAMFS_DIR"/{proc,sys,dev,tmp,etc,root,home/student,usr/bin,run}

echo -e "${CYAN}[5/6] Copiando Python 3 y librerías dinámicas del Host...${NC}"
PYTHON_BIN=$(which python3)
cp "$PYTHON_BIN" "$INITRAMFS_DIR/usr/bin/python3"

# Mapear las librerías dinámicas compartidas de forma exacta
for lib in $(ldd "$PYTHON_BIN" 2>/dev/null | grep -oE '/[^ ]+\.so[^ ]*'); do
  mkdir -p "$INITRAMFS_DIR$(dirname $lib)"
  cp -L "$lib" "$INITRAMFS_DIR$lib" 2>/dev/null || true
done

# Cargar la librería estándar nativa para habilitar os.splice()
PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
mkdir -p "$INITRAMFS_DIR/usr/lib/python${PYTHON_VER}"
cp -r /usr/lib/python3/* "$INITRAMFS_DIR/usr/lib/" 2>/dev/null || \
  cp -r /usr/lib/python${PYTHON_VER} "$INITRAMFS_DIR/usr/lib/" 2>/dev/null || true
ln -sf python3 "$INITRAMFS_DIR/usr/bin/python" 2>/dev/null || true

# Configuración de cuentas y entorno local
cat > "$INITRAMFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
student:x:1001:1001:student:/home/student:/bin/sh
EOF

cat > "$INITRAMFS_DIR/etc/group" << 'EOF'
root:x:0:
student:x:1001:student
EOF

cat > "$INITRAMFS_DIR/etc/profile" << 'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PS1='[\u@copy-fail \w]\$ '
EOF

# Script init maestro
cat > "$INITRAMFS_DIR/init" << 'INITEOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s
mount -t tmpfs none /tmp

modprobe algif_aead 2>/dev/null || true
modprobe authencesn 2>/dev/null || true

exec su - student
INITEOF
chmod +x "$INITRAMFS_DIR/init"

echo -e "${CYAN}[6/6] Empaquetando initramfs de forma nativa...${NC}"
cd "$INITRAMFS_DIR"
find . | cpio -o -H newc | gzip > "$BUILD_DIR/initramfs.cpio.gz"
echo -e "${GREEN}✓ rootfs generado de forma limpia.${NC}"
#!/bin/bash
# Runs inside Docker (q22e-ubuntu-builder).
# Expects: /in/base.tar.gz, /out/, optional /keys/authorized_keys
# Env: SIZE_GB, UBUNTU_CODENAME, NO_KEYS
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
update-binfmts --enable qemu-arm 2>/dev/null || true

SIZE_GB="${SIZE_GB:-2}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
NO_KEYS="${NO_KEYS:-1}"

ROOTFS=/work/rootfs
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo "extract base…"
tar -xzf /in/base.tar.gz -C "$ROOTFS"
chmod -R u+rwX "$ROOTFS"
chmod 755 "$ROOTFS/etc" 2>/dev/null || true
mkdir -p "$ROOTFS/etc/sudoers.d"
chmod 755 "$ROOTFS/etc/sudoers.d"

cp -a /usr/bin/qemu-arm-static "$ROOTFS/usr/bin/" 2>/dev/null \
  || cp -a /usr/bin/qemu-arm "$ROOTFS/usr/bin/qemu-arm-static"

mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
mount -o bind /dev "$ROOTFS/dev"
mount -o bind /dev/pts "$ROOTFS/dev/pts"
mount -o bind /run "$ROOTFS/run" 2>/dev/null || true

cat > "$ROOTFS/etc/resolv.conf" <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb http://ports.ubuntu.com/ubuntu-ports ${UBUNTU_CODENAME} main universe
deb http://ports.ubuntu.com/ubuntu-ports ${UBUNTU_CODENAME}-updates main universe
deb http://ports.ubuntu.com/ubuntu-ports ${UBUNTU_CODENAME}-security main universe
EOF

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  openssh-server ca-certificates \
  iproute2 iputils-ping net-tools vim-tiny
mkdir -p /root/.ssh /var/run/sshd
chmod 700 /root/.ssh
sed -i \"s/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config
sed -i \"s/^#\\?PasswordAuthentication.*/PasswordAuthentication no/\" /etc/ssh/sshd_config
sed -i \"s/^#\\?PubkeyAuthentication.*/PubkeyAuthentication yes/\" /etc/ssh/sshd_config
/usr/bin/ssh-keygen -A
echo cytatv-ubuntu >/etc/hostname
echo ubuntu-chroot >/etc/cytatv-sd-linux
[ -f /etc/debian_version ] || echo bookworm/sid >/etc/debian_version
: >/etc/machine-id
apt-get clean
rm -rf /var/lib/apt/lists/*
"

if [ "$NO_KEYS" = "0" ] && [ -f /keys/authorized_keys ]; then
  cp /keys/authorized_keys "$ROOTFS/root/.ssh/authorized_keys"
  chmod 600 "$ROOTFS/root/.ssh/authorized_keys"
  chown root:root "$ROOTFS/root/.ssh/authorized_keys"
  echo "SSH keys installed"
else
  echo "WARN: no authorized_keys"
fi

umount "$ROOTFS/dev/pts" 2>/dev/null || true
umount "$ROOTFS/dev" 2>/dev/null || true
umount "$ROOTFS/run" 2>/dev/null || true
umount "$ROOTFS/sys" 2>/dev/null || true
umount "$ROOTFS/proc" 2>/dev/null || true
rm -f "$ROOTFS/usr/bin/qemu-arm-static"

SIZE_MIB=$((SIZE_GB * 1024))
PART=/work/part.img
DISK=/out/ubuntu-chroot.img
rm -f "$PART" "$DISK"
dd if=/dev/zero of="$PART" bs=1M count=$((SIZE_MIB - 1)) status=none

mkfs.ext4 -F -b 4096 -I 256 -L ubuntu-chroot \
  -O extent,filetype,sparse_super,dir_index,resize_inode,has_journal,ext_attr,^64bit,^metadata_csum,^flex_bg,^huge_file,^ea_inode,^encrypt,^metadata_csum_seed \
  "$PART"

mkdir -p /work/mnt
mount -o loop "$PART" /work/mnt
rsync -aH --numeric-ids "$ROOTFS"/ /work/mnt/
sync
umount /work/mnt

dd if=/dev/zero of="$DISK" bs=1M count="$SIZE_MIB" status=none
sfdisk "$DISK" <<EOF
label: dos
label-id: 0x63796174
unit: sectors
2048,,83,*
EOF
dd if="$PART" of="$DISK" bs=1M seek=1 conv=notrunc status=progress
sync

echo "=== verify ==="
e2fsck -fy "$PART" | tail -5
mount -o loop "$PART" /work/mnt
test -f /work/mnt/lib/ld-linux-armhf.so.3 \
  || test -f /work/mnt/usr/lib/arm-linux-gnueabihf/ld-linux-armhf.so.3 \
  || { echo "FAIL: no dynamic linker"; exit 1; }
test -f /work/mnt/usr/sbin/sshd
test -f /work/mnt/etc/cytatv-sd-linux
head -5 /work/mnt/etc/os-release
du -sh /work/mnt
umount /work/mnt
ln -sfn ubuntu-chroot.img /out/linux.img
ls -lh "$DISK"
echo DONE

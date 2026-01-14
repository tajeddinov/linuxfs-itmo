# mount.sh

set -euo pipefail

HOST="ramil@127.0.0.1"
PORT="2222"
REMOTE_DIR="/home/ramil/linuxfs-itmo"
MP="/mnt/vt"

echo "[MOUNT] connect to ${HOST}:${PORT}:${REMOTE_DIR}"

ssh -t -p "${PORT}" "${HOST}" <<EOF
set -e

echo "[remote] cd ${REMOTE_DIR}"
cd ${REMOTE_DIR}

echo "[remote] umount old ${MP}"
sudo umount ${MP} 2>/dev/null || true

echo "[remote] rmmod old vtfs"
sudo rmmod vtfs 2>/dev/null || true

echo "[remote] insmod vtfs.ko"
sudo insmod vtfs.ko

echo "[remote] mkdir -p ${MP}"
sudo mkdir -p ${MP}

echo "[remote] mount -t vtfs none ${MP}"
sudo mount -t vtfs none ${MP}

echo "[remote] mount | grep vtfs"
mount | grep vtfs || true

echo "[remote] dmesg | tail -n 50"
sudo dmesg | tail -n 50

EOF

echo "[MOUNT] done"
# unmount.sh

set -euo pipefail

HOST="127.0.0.1"
PORT="2222"
USER="ramil"
MNT="/mnt/vt"
MOD="vtfs"

echo "[UNMOUNT] connect to ${USER}@${HOST}:${PORT} (mnt=${MNT}, mod=${MOD})"

ssh -t -p "${PORT}" "${USER}@${HOST}" <<EOF
set -e

echo "[1/4] Show current mount"
mount | grep -E " on ${MNT} type ${MOD}( |$)" || true

echo "[2/4] Unmount"
if mount | grep -qE " on ${MNT} type ${MOD}( |$)"; then
  sudo umount "${MNT}"
else
  echo "Not mounted, skip umount"
fi

echo "[3/4] Remove module"
if lsmod | awk '{print \$1}' | grep -qx "${MOD}"; then
  sudo rmmod "${MOD}"
else
  echo "Module not loaded, skip rmmod"
fi

echo "[4/4] Last kernel logs (tail)"
sudo dmesg | tail -n 80 || true

echo "[OK] unmount script finished"
EOF
# sync.sh

set -euo pipefail

HOST="ramil@127.0.0.1"
PORT="2222"
REMOTE_DIR="/home/ramil/linuxfs-itmo"

echo "[RSYNC] connect to ${HOST}:${PORT}:${REMOTE_DIR}"

rsync -az --delete \
  -e "ssh -p ${PORT}" \
  --exclude .git \
  --exclude .idea \
  --exclude '*.o' \
  --exclude '*.ko' \
  --exclude '*.mod*' \
  ./ "${HOST}:${REMOTE_DIR}/"

echo "[RSYNC] done"

echo "[BUILD] start"
ssh -t -p "${PORT}" "${HOST}" <<EOF
set -e
echo "[remote] cd ${REMOTE_DIR}"
cd ${REMOTE_DIR}

echo "[remote] make"
make

echo "[remote] ls -l vtfs.ko"
ls -l vtfs.ko

EOF
echo "[BUILD] done"
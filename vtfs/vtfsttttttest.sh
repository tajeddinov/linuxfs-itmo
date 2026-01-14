#!/usr/bin/env bash
set -euo pipefail

HOST="127.0.0.1"
PORT="2222"
USER="ramil"
REMOTE_TEST="/tmp/vtfs_tests.sh"

echo "=== VTFS: run tests via SSH ==="
echo "Target: ${USER}@${HOST}:${PORT}"
echo "Remote test path: ${REMOTE_TEST}"
echo

# --- 1) Upload test script to guest ---
echo "[1/3] Uploading test script to guest..."
ssh -p "${PORT}" "${USER}@${HOST}" "cat > '${REMOTE_TEST}'" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MP="/mnt/vt"
FAILS=0

say() { echo -e "$*"; }
ok()  { say "[ OK ] $*"; }
fail(){ say "[FAIL] $*"; FAILS=$((FAILS+1)); }

run() {
  say ">>> $*"
  eval "$@"
}

need_mounted() {
  mount | grep -q " on ${MP} type vtfs"
}

test_begin() { say ""; say "[TEST $1] $2"; }

# --- PREP ---
say "=== VTFS tests (Parts 3-9*) ==="
say "Mountpoint: ${MP}"

test_begin "0" "Проверка, что vtfs смонтирована"
run "mount | grep ' on ${MP} type vtfs' || true"
if need_mounted; then ok "vtfs смонтирована"; else fail "vtfs НЕ смонтирована"; fi

test_begin "0.1" "Очистка состояния (удаляем всё в ${MP}, если возможно)"
if need_mounted; then
  run "ls -la ${MP} || true"
  run "rm -rf ${MP}/* ${MP}/.[!.]* ${MP}/..?* 2>/dev/null || true"
  ok "попытались очистить точку монтирования"
else
  ok "пропуск очистки (не смонтировано)"
fi

test_begin "1" "Проверка что ${MP} — директория и права 777 (часть 3)"
if cd "${MP}" 2>/dev/null; then ok "cd в ${MP} работает"; else fail "cd в ${MP} не работает"; fi
run "ls -ld ${MP} || true"
PERM="$(stat -c '%A' "${MP}" 2>/dev/null || true)"
if [[ "${PERM}" == drwxrwxrwx* ]]; then ok "права директории 777"; else fail "права не 777 (stat=${PERM})"; fi

test_begin "2" "Проверка вывода содержимого директории (iterate) + '.' и '..'"
run "ls -la ${MP} || true"
if ls -a "${MP}" | grep -qx "."; then ok "есть '.'"; else fail "нет '.'"; fi
if ls -a "${MP}" | grep -qx ".."; then ok "есть '..'"; else fail "нет '..'"; fi

test_begin "3" "Навигация по директориям (часть 4): mkdir + cd + ls"
run "mkdir -p ${MP}/dir_nav 2>/dev/null || true"
if [[ -d "${MP}/dir_nav" ]]; then
  ok "создали директорию dir_nav"
  if cd "${MP}/dir_nav" 2>/dev/null; then ok "cd в dir_nav работает"; else fail "cd в dir_nav не работает"; fi
  run "cd ${MP}/dir_nav && pwd && ls -la || true"
else
  fail "mkdir не создал директорию (mkdir/rmdir ещё не работают?)"
fi
cd - >/dev/null 2>&1 || true

test_begin "4" "Создание/удаление файлов (часть 5): touch + ls + rm"
run "touch ${MP}/t1.txt 2>/dev/null || true"
if [[ -e "${MP}/t1.txt" ]]; then ok "touch создал файл t1.txt"; else fail "touch не создал файл"; fi
run "ls -la ${MP} | grep -E 't1.txt' || true"
run "rm -f ${MP}/t1.txt 2>/dev/null || true"
if [[ ! -e "${MP}/t1.txt" ]]; then ok "rm удалил файл"; else fail "rm не удалил файл"; fi

test_begin "5" "mkdir/rmdir (часть 7): пустая удаляется, непустая — нет"
run "mkdir ${MP}/d1 2>/dev/null || true"
if [[ -d "${MP}/d1" ]]; then ok "mkdir d1 ok"; else fail "mkdir d1 failed"; fi

run "rmdir ${MP}/d1 2>/dev/null || true"
if [[ ! -e "${MP}/d1" ]]; then ok "rmdir пустой директории ok"; else fail "rmdir пустой директории failed"; fi

run "mkdir ${MP}/d2 2>/dev/null || true"
run "touch ${MP}/d2/file 2>/dev/null || true"
set +e
OUT=$(rmdir "${MP}/d2" 2>&1)
RC=$?
set -e
say ">>> rmdir ${MP}/d2 (ожидаем ошибку)"
say "${OUT}"
if [[ $RC -ne 0 ]]; then ok "rmdir непустой директории запрещён"; else fail "rmdir непустой директории почему-то разрешён"; fi
run "rm -f ${MP}/d2/file 2>/dev/null || true"
run "rmdir ${MP}/d2 2>/dev/null || true"
if [[ ! -e "${MP}/d2" ]]; then ok "после очистки rmdir ok"; else fail "cleanup d2 failed"; fi

test_begin "6" "Чтение/запись (часть 8): printf/cat + запрет non-ASCII"
run "printf 'hello world from file1' > ${MP}/file1 2>/dev/null || true"
VAL="$(cat "${MP}/file1" 2>/dev/null || true)"
if [[ "${VAL}" == "hello world from file1" ]]; then ok "write+read ok"; else fail "неверное содержимое: '${VAL}'"; fi

run "printf 'test' > ${MP}/file1 2>/dev/null || true"
VAL2="$(cat "${MP}/file1" 2>/dev/null || true)"
if [[ "${VAL2}" == "test" ]]; then ok "перезапись ok"; else fail "перезапись сломана: '${VAL2}'"; fi

test_begin "6.1" "ASCII-символы: разрешены управляющие (например \\n и \\t)"
run "printf 'A\\tB\\nC' > ${MP}/ascii_ctl 2>/dev/null || true"
run "od -An -t u1 ${MP}/ascii_ctl | head -n 1 || true"
ok "управляющие ASCII не должны ломать запись"

test_begin "6.2" "Non-ASCII должны быть запрещены (пример: UTF-8 'привет')"
set +e
printf "привет" > "${MP}/ru.txt" 2>/dev/null
RC=$?
set -e
if [[ $RC -ne 0 ]]; then ok "non-ASCII отклонены (rc=${RC})"; else fail "non-ASCII почему-то записались"; fi

test_begin "7" "Жёсткие ссылки (часть 9): ln file1 file3, чтение совпадает"
run "printf 'DATA' > ${MP}/hl_src 2>/dev/null || true"
run "ln ${MP}/hl_src ${MP}/hl_link 2>/dev/null || true"
if [[ -e "${MP}/hl_link" ]]; then ok "ln создал hardlink"; else fail "ln не создал hardlink"; fi

A="$(cat "${MP}/hl_src" 2>/dev/null || true)"
B="$(cat "${MP}/hl_link" 2>/dev/null || true)"
if [[ "${A}" == "${B}" && "${A}" == "DATA" ]]; then ok "содержимое совпадает"; else fail "содержимое не совпадает: src='${A}' link='${B}'"; fi

test_begin "8" "Hardlink: запись через оригинал видна через ссылку"
run "printf 'NEW' > ${MP}/hl_src 2>/dev/null || true"
B2="$(cat "${MP}/hl_link" 2>/dev/null || true)"
if [[ "${B2}" == "NEW" ]]; then ok "изменение видно через ссылку"; else fail "изменение не видно: '${B2}'"; fi

test_begin "9" "Hardlink: rm оригинал, ссылка должна остаться рабочей"
run "rm -f ${MP}/hl_src 2>/dev/null || true"
set +e
B3="$(cat "${MP}/hl_link" 2>/dev/null)"
RC=$?
set -e
if [[ $RC -eq 0 ]]; then ok "после rm orig hardlink читается: '${B3}'"; else fail "после rm orig hardlink сломался"; fi

test_begin "10" "Hardlink запрещён для директорий"
run "mkdir -p ${MP}/dir_for_link 2>/dev/null || true"
set +e
OUT2=$(ln "${MP}/dir_for_link" "${MP}/dir_for_link2" 2>&1)
RC2=$?
set -e
say ">>> ln dir_for_link dir_for_link2 (ожидаем отказ)"
say "${OUT2}"
if [[ $RC2 -ne 0 ]]; then ok "hardlink для директорий запрещён"; else fail "hardlink для директорий почему-то разрешён"; fi

say ""
if [[ $FAILS -eq 0 ]]; then
  ok "ВСЕ ТЕСТЫ ПРОШЛИ"
  exit 0
else
  fail "ПРОВАЛЕНО ТЕСТОВ: $FAILS"
  exit 1
fi
EOF

# --- 2) chmod + run ---
echo "[2/3] chmod +x on guest..."
ssh -p "${PORT}" "${USER}@${HOST}" "chmod +x '${REMOTE_TEST}'"

echo "[3/3] Running tests on guest (with sudo)..."
# sudo нужно, если /mnt/vt root-owned; если у тебя всё доступно юзеру — убери sudo.
ssh -t -p "${PORT}" "${USER}@${HOST}" "sudo bash '${REMOTE_TEST}'"
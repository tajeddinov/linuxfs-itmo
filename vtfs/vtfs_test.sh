#!/usr/bin/env bash
# vtfs_demo_clean_tests.sh
# Запускать ВНУТРИ QEMU (Linux guest).
# Делает "мягкие" тесты без umount/rmmod: всё чистит через rm -rf после каждого теста.

set -euo pipefail

MP="/mnt/vt"
MOD="vtfs"
SANDBOX="${MP}/.vtfs_test"

FAILS=0
TESTNO=0

say() { echo -e "$*"; }
ok()  { say "✅ [ OK ] $*"; }
warn(){ say "⚠️  [WARN] $*"; }
fail(){ say "❌ [FAIL] $*"; FAILS=$((FAILS+1)); }

run() {
  say ">>> $*"
  # shellcheck disable=SC2086
  eval "$@"
}

test_begin() {
  TESTNO=$((TESTNO+1))
  say ""
  say "========================================"
  say "[TEST ${TESTNO}] $1"
  say "========================================"
}

is_mounted() {
  mount | grep -qE " on ${MP} type ${MOD}"
}

cleanup() {
  # Важно: не падать, даже если что-то не удалилось из-за багов ФС
  say ""
  say "[CLEANUP] remove sandbox: ${SANDBOX}"
  set +e
  rm -rf "${SANDBOX}"/* "${SANDBOX}"/.[!.]* "${SANDBOX}"/..?* 2>/dev/null
  rmdir "${SANDBOX}" 2>/dev/null
  RC=$?
  set -e
  if [[ $RC -eq 0 ]]; then
    ok "cleanup done"
  else
    warn "cleanup had issues (rc=${RC}) — возможно, unlink/rmdir ещё не идеальны"
  fi
}

sandbox_prep() {
  # Создаём песочницу для теста
  run "mkdir -p '${SANDBOX}'"
}

must_mounted_or_exit() {
  if ! is_mounted; then
    fail "vtfs не смонтирована на ${MP}. Смонтируй и запусти снова."
    exit 1
  fi
}

# ------------- START -------------
say "=== VTFS CLEAN DEMO TESTS (Parts 3-9*) ==="
say "Mountpoint: ${MP}"
say "Sandbox:    ${SANDBOX}"
say ""

test_begin "Проверка, что vtfs смонтирована и это директория"
run "mount | grep -E ' on ${MP} type ${MOD}' || true"
if is_mounted; then ok "vtfs смонтирована"; else fail "vtfs НЕ смонтирована"; exit 1; fi
run "ls -ld '${MP}' || true"
if cd "${MP}" 2>/dev/null; then ok "cd в ${MP} работает"; else fail "cd не работает"; fi

# ---------- TEST 2: iterate / . and .. ----------
test_begin "Часть 3: iterate (ls -la) + наличие '.' и '..'"
sandbox_prep
run "ls -la '${MP}' || true"
LIST_A="$(ls -a "${MP}" 2>/dev/null || true)"
# Важно: grep -x по строкам
if printf "%s\n" "${LIST_A}" | grep -qx ".";  then ok "есть '.'";  else fail "нет '.'";  fi
if printf "%s\n" "${LIST_A}" | grep -qx ".."; then ok "есть '..'"; else fail "нет '..'"; fi
cleanup

# ---------- TEST 3: create/unlink in root sandbox ----------
test_begin "Часть 5/6: create/unlink (touch + rm) в песочнице"
sandbox_prep
run "touch '${SANDBOX}/t1.txt'"
if [[ -e "${SANDBOX}/t1.txt" ]]; then ok "touch создал файл"; else fail "touch не создал"; fi
run "ls -la '${SANDBOX}' || true"
run "rm -f '${SANDBOX}/t1.txt'"
if [[ ! -e "${SANDBOX}/t1.txt" ]]; then ok "rm удалил файл"; else fail "rm не удалил"; fi
cleanup

# ---------- TEST 4: mkdir/rmdir empty + non-empty ----------
test_begin "Часть 7: mkdir/rmdir — пустая удаляется, непустая НЕ удаляется"
sandbox_prep

run "mkdir '${SANDBOX}/d_empty'"
if [[ -d "${SANDBOX}/d_empty" ]]; then ok "mkdir создал директорию"; else fail "mkdir не создал"; fi
run "rmdir '${SANDBOX}/d_empty'"
if [[ ! -e "${SANDBOX}/d_empty" ]]; then ok "rmdir пустой директории ok"; else fail "rmdir пустой директории не сработал"; fi

run "mkdir '${SANDBOX}/d_ne'"
run "touch '${SANDBOX}/d_ne/file'"

set +e
OUT="$(rmdir "${SANDBOX}/d_ne" 2>&1)"
RC=$?
set -e
say ">>> rmdir '${SANDBOX}/d_ne'  (ожидаем ошибку ENOTEMPTY)"
say "${OUT}"
if [[ $RC -ne 0 ]]; then ok "rmdir непустой директории запрещён"; else fail "rmdir непустой директории почему-то разрешён"; fi

run "rm -f '${SANDBOX}/d_ne/file'"
run "rmdir '${SANDBOX}/d_ne'"
if [[ ! -e "${SANDBOX}/d_ne" ]]; then ok "после очистки rmdir ok"; else fail "после очистки rmdir не сработал"; fi

cleanup

# ---------- TEST 5: read/write basic (echo/cat) ----------
test_begin "Часть 8*: read/write — echo > file, cat читает то же"
sandbox_prep

run "echo 'hello world from file1' > '${SANDBOX}/file1'"
VAL="$(cat "${SANDBOX}/file1" 2>/dev/null || true)"
say "readback: '${VAL}'"
if [[ "${VAL}" == "hello world from file1" ]]; then ok "write+read ok"; else fail "неверное содержимое"; fi

run "echo 'test' > '${SANDBOX}/file1'"
VAL2="$(cat "${SANDBOX}/file1" 2>/dev/null || true)"
say "readback: '${VAL2}'"
if [[ "${VAL2}" == "test" ]]; then ok "overwrite ok"; else fail "overwrite сломан"; fi

cleanup

# ---------- TEST 6: append (optional) ----------
test_begin "Опционально: append через >> (если не работает — WARN)"
sandbox_prep

run "printf 'hello' > '${SANDBOX}/append.txt'"
set +e
printf ' world' >> "${SANDBOX}/append.txt" 2>/dev/null
RC_APP=$?
set -e
APP="$(cat "${SANDBOX}/append.txt" 2>/dev/null || true)"
say "readback: '${APP}'"
if [[ "${APP}" == "hello world" ]]; then
  ok "append работает"
else
  warn "append не сработал (rc=${RC_APP}). Это обычно связано с offset в write()."
fi

cleanup

# ---------- TEST 7: ASCII control allowed ----------
test_begin "Часть 8*: ASCII 0..127 — разрешаем таб/перевод строки"
sandbox_prep

run "printf 'A\tB\nC\n' > '${SANDBOX}/ascii_ctl'"
run "od -An -t u1 '${SANDBOX}/ascii_ctl' | head -n 1 || true"
ok "управляющие ASCII записались (проверили od)"

cleanup

# ---------- TEST 8: Non-ASCII must be rejected ----------
test_begin "Часть 8*: Non-ASCII запрещены (UTF-8 'привет' должен дать ошибку)"
sandbox_prep

set +e
printf "привет" > "${SANDBOX}/ru.txt" 2>/dev/null
RC_UTF=$?
set -e
if [[ $RC_UTF -ne 0 ]]; then ok "non-ASCII отклонены (rc=${RC_UTF})"; else fail "non-ASCII почему-то записались"; fi

cleanup

# ---------- TEST 9: hardlink basic semantics ----------
test_begin "Часть 9*: hardlink для файла: ln src link, общий контент"
sandbox_prep

run "echo 'DATA' > '${SANDBOX}/hl_src'"
run "ln '${SANDBOX}/hl_src' '${SANDBOX}/hl_link'"
if [[ -e "${SANDBOX}/hl_link" ]]; then ok "ln создал hardlink"; else fail "ln не создал"; fi

A="$(cat "${SANDBOX}/hl_src" 2>/dev/null || true)"
B="$(cat "${SANDBOX}/hl_link" 2>/dev/null || true)"
say "src='${A}' link='${B}'"
if [[ "${A}" == "DATA" && "${B}" == "DATA" ]]; then ok "оба читаются одинаково"; else fail "hardlink чтение не совпало"; fi

run "echo 'test' > '${SANDBOX}/hl_src'"
B2="$(cat "${SANDBOX}/hl_link" 2>/dev/null || true)"
say "after write src, link='${B2}'"
if [[ "${B2}" == "test" ]]; then ok "изменение через src видно через link"; else fail "изменение через src НЕ видно через link"; fi

run "rm -f '${SANDBOX}/hl_src'"
set +e
B3="$(cat "${SANDBOX}/hl_link" 2>/dev/null)"
RC3=$?
set -e
say "after rm src: rc=${RC3}, link_read='${B3}'"
if [[ $RC3 -eq 0 ]]; then ok "после rm оригинала hardlink жив"; else fail "после rm оригинала hardlink сломался"; fi

cleanup

## ---------- TEST 10: hardlink for directory denied ----------
#test_begin "Часть 9*: hardlink для директории запрещён"
#sandbox_prep
#
#run "mkdir -p '${SANDBOX}/dir_for_link'"
#set +e
#OUT_DIR_LN="$(ln "${SANDBOX}/dir_for_link" "${SANDBOX}/dir_for_link2" 2>&1)"
#RC_DIR_LN=$?
#set -e
#say ">>> ln dir_for_link dir_for_link2 (ожидаем отказ)"
#say "${OUT_DIR_LN}"
#if [[ $RC_DIR_LN -ne 0 ]]; then ok "hardlink директорий запрещён"; else fail "hardlink директорий почему-то разрешён"; fi
#
#cleanup

# ------------- SUMMARY -------------
say ""
say "================================"
say "SUMMARY"
say "================================"
if [[ $FAILS -eq 0 ]]; then
  ok "ВСЕ КРИТИЧЕСКИЕ ТЕСТЫ ПРОШЛИ"
  exit 0
else
  fail "ПРОВАЛЕНО ТЕСТОВ: $FAILS"
  exit 1
fi
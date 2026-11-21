#!/usr/bin/env bash
# 승인된 테스트가 어떤 방법으로든(Edit, sed -i, >, cp, mv, rm …) 바뀌었으면 막는다.
#   check-approved.sh commit : git commit 직전 (PreToolUse Bash|PowerShell)
#   check-approved.sh stop   : Claude가 응답을 끝내기 직전 (Stop). 한 번 멈춰 세운 뒤엔 보내 준다(무한 반복 방지).
# apps/*/tests/.approved 의 해시와 지금 파일의 해시(\r 을 지운 내용)를 비교한다.
#   check-approved.sh lock apps/<앱>          : (graph.sh) 잠금 상태. 0 = 있고 해시 일치, 1 = 잠금 파일 없음(또는 빈 목록), 2 = 해시 다름
#   check-approved.sh listed apps/<앱> <경로> : (graph.sh) 그 파일이 잠금 목록에 있으면 0
#   check-approved.sh files apps/<앱>         : (graph.sh) 잠긴 파일 경로(저장소 기준)를 한 줄씩. 잠금 없으면 빈 출력
#   check-approved.sh count apps/<앱>         : (graph.sh) 잠긴 파일 안의 테스트 정의 수. 잠금 없으면 0
#   check-approved.sh listfile apps/<앱>      : (graph.sh) 잠금 파일 경로(저장소 기준) 한 줄
#       JS·TS: test('…')·it('…') (+ .only·.fixme·.fail·.concurrent) — 제목 글자로 시작하는 것만(describe·step·hook 제외)
#       Python: def test_… / Java·Kotlin: @Test, @ParameterizedTest, @RepeatedTest
# 종료 코드 2 = 막기 (stderr 내용이 Claude에게 전달된다), 0 = 통과. jq 없이 동작한다.

mode="$1"

if [ "$mode" = "listfile" ]; then echo "${2%/}/tests/.approved"; exit 0; fi   # (graph.sh) 잠금 파일 경로 — 준비 코드에서 이것만 뺀다

if [ "$mode" = "files" ] || [ "$mode" = "count" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
  cd "$root" || exit 1
  list="${2%/}/tests/.approved"
  if [ ! -f "$list" ]; then [ "$mode" = "count" ] && echo 0; exit 0; fi
  if [ "$mode" = "files" ]; then sed -n 's/^[0-9a-f]\{64\}  //p' "$list"; exit 0; fi
  n=0
  while IFS= read -r p; do
    [ -f "$p" ] || continue
    case "$p" in
      *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) c="$(tr -d '\r' < "$p" | grep -Eo "(^|[^A-Za-z0-9_.\$])(test|it)(\.(only|fixme|fail|concurrent))?[[:space:]]*\([[:space:]]*['\"\`]" | grep -c '')" ;;
      *.py) c="$(tr -d '\r' < "$p" | grep -Ec '^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test')" ;;
      *.java|*.kt) c="$(tr -d '\r' < "$p" | grep -Ec '^[[:space:]]*@(Test|ParameterizedTest|RepeatedTest)\b')" ;;
      *) c=0 ;;
    esac
    n=$((n + c))
  done <<< "$(sed -n 's/^[0-9a-f]\{64\}  //p' "$list")"
  echo "$n"; exit 0
fi

if [ "$mode" = "lock" ] || [ "$mode" = "listed" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
  cd "$root" || exit 1
  list="${2%/}/tests/.approved"
  [ -f "$list" ] || exit 1
  if [ "$mode" = "listed" ]; then
    sed -n 's/^[0-9a-f]\{64\}  //p' "$list" | grep -qxF "$3"; exit $?
  fi
  n=0; bad=""
  while IFS= read -r line; do
    h="$(printf '%s' "$line" | sed -n 's/^\([0-9a-f]\{64\}\)  .*/\1/p')"
    [ -z "$h" ] && continue
    n=$((n+1)); p="$(printf '%s' "$line" | sed 's/^[0-9a-f]\{64\}  //')"
    if [ ! -f "$p" ] || [ "$(tr -d '\r' < "$p" | sha256sum | cut -c1-64)" != "$h" ]; then bad="$bad $p"; fi
  done < "$list"
  [ $n -eq 0 ] && exit 1
  [ -n "$bad" ] && { echo "[승인 테스트] 해시 다름:$bad" >&2; exit 2; }
  exit 0
fi

input="$(cat)"

if [ "$mode" = "commit" ]; then
  printf '%s' "$input" | grep -q 'git commit' || exit 0
fi
if [ "$mode" = "stop" ]; then
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

bad=""
for list in apps/*/tests/.approved; do
  [ -f "$list" ] || continue
  while IFS= read -r line; do
    h="$(printf '%s' "$line" | sed -n 's/^\([0-9a-f]\{64\}\)  .*/\1/p')"
    [ -z "$h" ] && continue
    p="$(printf '%s' "$line" | sed 's/^[0-9a-f]\{64\}  //')"
    if [ ! -f "$p" ]; then
      bad="$bad
- $p (지워짐)"
      continue
    fi
    now="$(tr -d '\r' < "$p" | sha256sum | cut -c1-64)"
    [ "$now" = "$h" ] || bad="$bad
- $p"
  done < "$list"
done

[ -z "$bad" ] && exit 0

echo "[승인 테스트] 승인된 테스트가 바뀜:$bad
승인된 테스트는 사장 허락 없이 고치지 않습니다. git으로 되돌리거나(커밋된 적 없으면 고치기 전 내용으로 직접 되돌림) 사장 승인을 받아라.
사장이 바뀐 내용을 허락했다면 사장이 직접 다시 잠근다: ! bash .claude/hooks/approve-tests.sh apps/<앱>" >&2
exit 2

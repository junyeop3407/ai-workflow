#!/usr/bin/env bash
# 승인된 테스트가 어떤 방법으로든(Edit, sed -i, >, cp, mv, rm …) 바뀌었으면 막는다.
#   check-approved.sh commit : git commit 직전 (PreToolUse Bash|PowerShell)
#   check-approved.sh stop   : Claude가 응답을 끝내기 직전 (Stop). 한 번 멈춰 세운 뒤엔 보내 준다(무한 반복 방지).
# apps/*/tests/.approved 의 해시와 지금 파일의 해시(\r 을 지운 내용)를 비교한다.
# 종료 코드 2 = 막기 (stderr 내용이 Claude에게 전달된다), 0 = 통과. jq 없이 동작한다.

mode="$1"
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

echo "승인된 테스트가 바뀜:$bad
승인된 테스트는 사장 허락 없이 고치지 않습니다. git으로 되돌리거나(커밋된 적 없으면 고치기 전 내용으로 직접 되돌림) 사장 승인을 받아라.
사장이 바뀐 내용을 허락했다면 사장이 직접 다시 잠근다: ! bash .claude/hooks/approve-tests.sh apps/<앱>" >&2
exit 2

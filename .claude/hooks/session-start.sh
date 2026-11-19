#!/usr/bin/env bash
# 세션을 새로 열 때(SessionStart, startup) 한 번: 예약 작업 대신 "사장이 작업할 때만" 도는 점검을 알린다.
#   1. 진행 중인 앱(HANDOFF의 현재 단계가 완료가 아니고 테스트 실행 줄이 있는 앱) 목록
#      → Claude가 test-runner로 한 번 돌려 깨진 것을 맨 먼저 알린다 (CLAUDE.md "새 세션 시작")
#   2. 마지막 주간 회고(docs/last-weekly-review.txt)에서 7일이 지났으면 "/weekly-review 할까요?"를 한 번만 묻게 한다
# 날짜 계산을 모델에 맡기면 틀리기 쉬워 여기서 한다. 아무것도 막지 않는다(항상 exit 0). jq 없이 동작한다.

input="$(cat)"
# 새로 시작할 때만 (resume·clear·compact 에서는 다시 알리지 않음)
src="$(printf '%s' "$input" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[ -n "$src" ] && [ "$src" != "startup" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

msg=""

# 1. 진행 중인 앱
apps=""
for h in apps/*/HANDOFF.md; do
  [ -f "$h" ] || continue
  grep -q '테스트 실행:' "$h" || continue
  grep -m1 '현재 단계:' "$h" | grep -q '완료' && continue
  apps="$apps $(basename "$(dirname "$h")")"
done
if [ -n "$apps" ]; then
  msg="세션 시작 점검: 진행 중인 앱($apps ) — git pull 뒤 test-runner로 각 앱 테스트를 한 번 돌려 깨진 것이 있으면 다른 일보다 먼저 사장에게 알리세요."
fi

# 2. 주간 회고
to_epoch() { date -d "$1" +%s 2>/dev/null || date -j -f %Y-%m-%d "$1" +%s 2>/dev/null; }
last="$(grep -Eom1 '[0-9]{4}-[0-9]{2}-[0-9]{2}' docs/last-weekly-review.txt 2>/dev/null)"
due=""
if [ -z "$last" ]; then
  due="아직 기록 없음"
else
  le="$(to_epoch "$last")"; ne="$(date +%s)"
  if [ -n "$le" ]; then
    days=$(( (ne - le) / 86400 ))
    [ "$days" -ge 7 ] && due="마지막 $last, ${days}일 지남"
  fi
fi
if [ -n "$due" ]; then
  msg="$msg 주간 회고($due): 사장에게 '/weekly-review 할까요?'를 이 세션에서 딱 한 번만 물으세요(AskUserQuestion). 거절하면 이 세션에서는 다시 묻지 마세요."
fi

[ -z "$msg" ] && exit 0
cat <<JSON
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"$msg"}}
JSON
exit 0

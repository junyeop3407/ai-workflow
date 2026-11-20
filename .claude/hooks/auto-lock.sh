#!/usr/bin/env bash
# 첫 테스트 잠금을 자동으로 한다 — graph.sh가 tc(테스트 코드) 노드를 통과시킨 직후 부른다.
# 사용: bash .claude/hooks/auto-lock.sh apps/<앱>
# 처음 한 번만 잠근다. 아래가 모두 맞을 때만 approve-tests.sh 를 부르고, 하나라도 아니면 거부(exit 1)한다.
#   1. state.json 이 정상(graph.sh 형식 검사 통과)
#   2. approvals 에 ok-tl(★ 테스트 승인) 기록이 있다
#   3. tc(테스트 코드) 가 통과
#   4. 잠금 파일(tests/.approved)이 지금 없다
#   5. state.json log 에 이전 잠금 기록이 없다
#   6. git 기록에도 그 앱의 tests/.approved 가 한 번도 없었다
# 이미 잠긴 뒤 다시 잠그는 것(승인된 테스트를 바꾼 뒤)은 지금처럼 사장만 한다:
#   ! bash .claude/hooks/approve-tests.sh apps/<앱>
# 남은 위험: ok-tl 승인 기록을 꾸미면 사장이 안 본 목록이 잠길 수 있다 → qa-reviewer 가 approvals·log 와 git log 를 대조한다.

app="${1%/}"
H="$(cd "$(dirname "$0")" && pwd)"
G="$H/../skills/build-app/graph.sh"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "git 저장소 안에서 실행하세요." >&2; exit 1; }
cd "$root" || exit 1
case "$app" in apps/?*) ;; *) echo "사용법: bash .claude/hooks/auto-lock.sh apps/<앱>" >&2; exit 1 ;; esac
no() { echo "자동 잠금 거부: $1" >&2; exit 1; }

bash "$G" current "$app" </dev/null >/dev/null 2>&1 || no "state.json 이 없거나 깨졌습니다."
bash "$G" get "$app" approval ok-tl </dev/null >/dev/null 2>&1 || no "★ 테스트 승인(ok-tl) 기록이 없습니다."
[ "$(bash "$G" get "$app" status tc </dev/null 2>/dev/null)" = "통과" ] || no "테스트 코드(tc)가 아직 통과가 아닙니다."
[ -e "$app/tests/.approved" ] && no "이미 잠겨 있습니다. 다시 잠그는 것은 사장만: ! bash .claude/hooks/approve-tests.sh $app"
bash "$G" get "$app" locked </dev/null >/dev/null 2>&1 && no "이전 잠금 기록이 있습니다. 다시 잠그는 것은 사장만."
[ -n "$(git log --all --oneline -- "$app/tests/.approved" 2>/dev/null | head -n1)" ] && no "git 기록에 잠금 파일이 있었습니다. 다시 잠그는 것은 사장만."

bash "$H/approve-tests.sh" "$app"

#!/usr/bin/env bash
# 세션을 새로 열 때(SessionStart, startup) 한 번: 예약 작업 대신 "사장이 작업할 때만" 도는 점검을 알린다.
#   1. 진행 중인 앱(HANDOFF의 현재 단계가 완료가 아니고 테스트 실행 줄이 있는 앱) 목록
#      → Claude가 test-runner로 한 번 돌려 깨진 것을 맨 먼저 알린다 (CLAUDE.md "새 세션 시작")
#   2. 마지막 주간 회고(docs/last-weekly-review.txt)에서 7일이 지났으면 "/weekly-review 할까요?"를 한 번만 묻게 한다
# 날짜 계산을 모델에 맡기면 틀리기 쉬워 여기서 한다. 아무것도 막지 않는다(항상 exit 0). jq 없이 동작한다.

input="$(cat)"
#   3. (그래프) 진행 중인 앱마다 graph.sh status --short 한 줄 + 멈춤 이유 — startup·resume·compact·clear 모두에서
#      (1·2는 새로 시작할 때만)
src="$(printf '%s' "$input" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

msg=""
G="$(cd "$(dirname "$0")" && pwd)/../skills/build-app/graph.sh"
graph=""
for s in apps/*/state.json; do
  [ -f "$s" ] && [ -f "$G" ] || continue
  a="$(dirname "$s")"
  line="$(bash "$G" status "$a" --short </dev/null 2>&1)"
  [ $? -eq 3 ] && line="[그래프 $(basename "$a")] state.json 이 깨졌습니다 — 추측해서 고치지 말고 사장에게 알리세요."
  printf '%s' "$line" | grep -q '끝(완료)' && continue
  graph="$graph $line /"
done
[ -n "$graph" ] && msg="그래프 상태(state.json의 현재 노드부터 자동으로 이어 가세요, 멈춤은 graph.md 다섯 가지뿐):$graph"

if [ -n "$src" ] && [ "$src" != "startup" ]; then
  [ -z "$msg" ] && exit 0
  msg="$(printf '%s' "$msg" | tr '"\\\t\r\n' "'/   ")"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
  exit 0
fi

# 1. 진행 중인 앱
apps=""
for h in apps/*/HANDOFF.md; do
  [ -f "$h" ] || continue
  grep -q '테스트 실행:' "$h" || continue
  grep -m1 '현재 단계:' "$h" | grep -q '완료' && continue
  apps="$apps $(basename "$(dirname "$h")")"
done
if [ -n "$apps" ]; then
  msg="$msg 세션 시작 점검: 진행 중인 앱($apps ) — git pull 뒤 test-runner로 각 앱 테스트를 한 번 돌려 깨진 것이 있으면 다른 일보다 먼저 사장에게 알리세요."
fi

# 1-2. 두 컴퓨터 동기화 (집 Windows ↔ 밖 Mac, 동시에는 안 씀 — 사장 2026-11-23)
#      원격을 받아(fetch, 읽기만) 받을 것·안 올린 것·두 갈래·다른 컴퓨터의 임시 브랜치(wip/…)를 알린다. 고치지는 않는다.
# git 자체 훅(.githooks/pre-push: main으로 가는 커밋은 테스트 통과만) — 컴퓨터마다 이 저장소 설정으로 연결
if [ -f .githooks/pre-push ] && [ "$(git config --local --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then
  git config --local core.hooksPath .githooks && msg="$msg git 훅 경로를 .githooks 로 연결함(main push 전 테스트 확인)."
fi
if [ "${SYNC_CHECK:-1}" = 1 ] && git remote get-url origin >/dev/null 2>&1; then
  case "$(uname -s)" in Darwin) here=Mac ;; MINGW*|MSYS*|CYGWIN*) here=Windows ;; *) here="$(uname -s)" ;; esac
  sync=""
  if GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 fetch --quiet origin </dev/null >/dev/null 2>&1; then
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
    if [ -n "$up" ]; then
      set -- $(git rev-list --left-right --count "$up...HEAD" 2>/dev/null); behind="${1:-0}"; ahead="${2:-0}"
      if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
        sync="$sync 두 갈래가 생김(받을 커밋 ${behind}개 + 이 컴퓨터에만 있는 커밋 ${ahead}개): 다른 일을 하기 전에 사장에게 알리고 git pull 로 합치세요. 충돌이 나면 멈추고 쉬운 말로 알리세요."
      elif [ "$behind" -gt 0 ]; then
        sync="$sync 다른 컴퓨터에서 한 커밋 ${behind}개가 있음: 먼저 git pull."
      elif [ "$ahead" -gt 0 ]; then
        sync="$sync 이 컴퓨터에 아직 안 올린 커밋 ${ahead}개: 지난번 /handoff 를 빠뜨렸을 수 있음 — 사장에게 알리고 git push."
      fi
    fi
    wips="$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/wip/ 2>/dev/null | sed 's#^origin/##' | paste -sd, -)"
    br="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"
    [ -n "$wips" ] && case ",$wips," in
      *",$br,"*) sync="$sync 지금 임시 브랜치 $br 에서 이어 하는 중(테스트가 다 통과하면 /handoff 로 main에 합침)." ;;
      *) sync="$sync 원격에 다른 컴퓨터가 구현 중에 올린 임시 브랜치가 있음($wips): 그 앱을 이어 하려면 git switch <그 브랜치> 후 git pull." ;;
    esac
  else
    sync="$sync 원격(GitHub)을 확인하지 못함(인터넷·로그인): 다른 컴퓨터 작업을 받았는지 모름 — 사장에게 알리세요."
  fi
  dirty="$(git status --porcelain 2>/dev/null | grep -c .)"
  [ "$dirty" -gt 0 ] && sync="$sync 커밋 안 한 변경 ${dirty}개가 이 컴퓨터에 있음(지난번 이 컴퓨터에서 하던 것)."
  lastpc="$(grep -m1 '^마지막 작업 컴퓨터:' HANDOFF.md 2>/dev/null | sed 's/^마지막 작업 컴퓨터:[[:space:]]*//')"
  msg="$msg 두 컴퓨터 점검(지금: $here${lastpc:+, 지난번: $lastpc}):${sync:- 받을 것·안 올린 것 없음.}"
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
msg="$(printf '%s' "$msg" | tr '"\\\t\r\n' "'/   ")"   # JSON 이 깨지지 않게
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0

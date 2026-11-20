#!/usr/bin/env bash
# Stop: 그래프 자동 진행. 앱 작업 턴(.git/graph-turn)이거나 앱 코드가 state.json 보다 새로울 때만 본다.
#   1. 구현 노드(bb·bf)가 "진행"이면 graph.sh loop 로 통과 검사를 직접 돌린다(/goal 대신 자동 루프).
#      실패 → 막고 "계속 고쳐라"(회차는 state.json 에 셈, stop_hook_active 에 기대지 않음)
#      통과 → graph.sh 가 자동 pass → 막고 "다음 노드를 시작하라"
#      15회 초과·같은 실패 3연속 → 사장 보고 상태로 바꾸고 한 번 막아 보고하게 → 다음 Stop 부터 통과
#   2. 그 밖의 "진행"·"승인" 노드를 두고 멈추려 하면 막는다. 같은 state 로 3번째 멈추려 하면 사장 보고(②)로 바꿈.
#   3. 정당한 멈춤(사장대기 ①④⑤ · 사장보고 ② · 도구없음 ③ · 확인필요)이면 통과.
#      단 ★ 대기 중인데 앱 코드가 state.json 보다 새로우면 한 번 알림(수정 시각 비교 — 사장 결정으로 유지).
#   4. state.json 이 깨졌으면 한 번 알림. 앱 코드는 바뀌었는데 state.json 이 없으면 한 번 알림.
# 공식 문서: https://code.claude.com/docs/en/hooks#stop-input — "The count of consecutive continuations resets
#   each time Claude calls a tool." 고치는 회차마다 도구를 쓰므로 8회 연속 한도에 걸리지 않는다.
# 종료 코드 2 = 막기(stderr 가 Claude 에게 감), 0 = 통과. jq 없이 동작한다.

input="$(cat)"
active=""; printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && active=1
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0
gd="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
G="$(cd "$(dirname "$0")" && pwd)/../skills/build-app/graph.sh"
[ -f "$G" ] || exit 0
turn=""; [ -f "$gd/graph-turn" ] && turn=1

msgs=""
add() { msgs="$msgs
$1"; }
code_newer() { # 앱 코드(문서·state·빌드 결과 제외) 중 state.json 보다 새로운 파일 하나
  find "$1" -type f -newer "$1/state.json" ! -name state.json ! -name '*.md' ! -name .redteam-needed \
    ! -path '*/docs/*' ! -path '*/node_modules/*' ! -path '*/build/*' ! -path '*/dist/*' ! -path '*/.gradle/*' \
    ! -path '*/target/*' ! -path '*/test-results/*' ! -path '*/playwright-report/*' 2>/dev/null | head -n1
}

for s in apps/*/state.json; do
  [ -f "$s" ] || continue
  app="$(dirname "$s")"; name="$(basename "$app")"
  newer="$(code_newer "$app")"
  [ -z "$turn" ] && [ -z "$newer" ] && continue
  nodes="$(bash "$G" current "$app" --status </dev/null 2>/dev/null)"; rc=$?
  if [ $rc -eq 3 ]; then
    [ -z "$active" ] && add "[그래프 $name] state.json 이 깨졌거나 잠금 기록과 잠금 파일이 맞지 않습니다 — 추측해서 고치지 말고 사장에게 알리세요."
    continue
  fi
  [ $rc -eq 0 ] && [ -n "$nodes" ] || continue

  # 1. 구현 노드 자동 루프
  if printf '%s\n' "$nodes" | grep -Eq '^(bb|bf):진행$'; then
    out="$(bash "$G" loop "$app" </dev/null 2>&1)"; lrc=$?
    case $lrc in 20|21|22) add "$out" ;; esac
    continue
  fi

  # 2·3. 정당한 멈춤인지
  ill=""; star=""
  while IFS=: read -r id stv; do
    [ -z "$id" ] && continue
    case "$stv" in
      사장대기) case "$id" in ok-*|pub) star=1 ;; esac ;;
      사장보고|도구없음|확인필요) ;;
      *) ill="$ill $id" ;;
    esac
  done <<< "$nodes"
  if [ -n "$ill" ]; then
    cs="$(cksum < "$s" | cut -d' ' -f1)"
    prev="$(cat "$gd/graph-stop-$name" 2>/dev/null)"
    if [ "${prev%% *}" = "$cs" ]; then cnt=$(( ${prev##* } + 1 )); else cnt=1; fi
    echo "$cs $cnt" > "$gd/graph-stop-$name"
    first="$(printf '%s' "$ill" | awk '{ print $1 }')"
    if [ $cnt -ge 3 ]; then
      bash "$G" stuck "$app" "$first" 보고 "진행 노드를 두고 같은 상태로 3번 멈추려 함" </dev/null >/dev/null 2>&1
      add "[그래프 $name·$first] 같은 상태로 3번 멈추려 했습니다 → 사장 보고(②)로 바꿨습니다. 무엇이 막혔는지 + 보기 2~3개 + 추천으로 보고하세요."
    else
      add "[그래프 $name] 진행 중인 노드($ill )를 두고 멈추려 합니다. 다음 노드로 넘어가거나(graph.sh pass / fail), 멈춰야 하면 다섯 가지(①★ ②보고 ③도구 없음 ④비용 ⑤안전장치) 중 무엇인지 graph.sh 로 남기세요(stuck / wait / usage). \"다음 단계 진행할까요?\"는 묻지 않습니다."
    fi
  elif [ -n "$star" ] && [ -n "$newer" ] && [ -z "$active" ]; then
    add "[그래프 $name] ★ 승인 대기 중인데 앱 코드($newer)가 state.json 보다 새롭습니다. ★ OK 전에 다음 일을 시작하지 않습니다 — 되돌리거나, 정상 작업이면 graph.sh 로 상태를 맞추세요."
  fi
done

# 4. 앱 코드는 바뀌었는데 state.json 이 없음
if [ -n "$turn" ] && [ -z "$active" ]; then
  for d in apps/*/; do
    d="${d%/}"; [ -d "$d" ] || continue; [ -f "$d/state.json" ] && continue
    [ -n "$(git status --porcelain -- "$d" 2>/dev/null | head -n1)" ] || continue
    add "[그래프 $(basename "$d")] 앱 파일이 바뀌었는데 state.json 이 없습니다. 새 앱: graph.sh init $d / 그래프 이전 앱: graph.sh migrate $d"
  done
fi

[ -z "$msgs" ] && exit 0
printf '%s\n' "${msgs#?}" >&2
exit 2

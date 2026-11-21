#!/usr/bin/env bash
# 바뀐 앱의 테스트를 돌려서, 실패하면 막는다.
#   check-tests.sh commit : git commit 직전 (PreToolUse). 실패하면 커밋을 막는다.
#   check-tests.sh stop   : Claude가 응답을 끝내기 직전 (Stop). 실패하면 한 번 멈춰 세운다.
# 테스트 명령은 apps/<앱>/HANDOFF.md 의 "테스트 실행: `명령`" 줄에서 읽는다.
# 그 줄이 없는 앱(아직 테스트를 만들기 전 단계)은 건너뛴다.
# 그래프(apps/<앱>/state.json, graph.sh current로 읽음)에 따라 줄을 고른다:
#   현재 노드가 bb·cb(백엔드 구현 중)  → "백엔드 테스트: `명령`" 줄 (없으면 테스트 실행 줄)
#   그 밖, 또는 state.json 없음·깨짐     → "테스트 실행:" 줄 (안전한 쪽)
#   stop 모드에서 bb·bf가 "진행"이면 그 앱은 건너뛴다 — graph-stop.sh 자동 루프가 같은 검사를 한다(두 번 안 돌림).
#   check-tests.sh app apps/<앱> [백엔드] : (graph.sh) 그 앱의 줄을 바로 실행하고 출력 전체를 보여 줌. 0 통과 / 1 실패·줄 없음
# 종료 코드 2 = 막기 (stderr 내용이 Claude에게 전달된다), 0 = 통과.

mode="$1"
G="$(cd "$(dirname "$0")" && pwd)/../skills/build-app/graph.sh"

# 앱 하나의 검사 줄 실행: run_app <앱> <줄 이름> → RUN_OUT, 종료 코드 0 통과 / 1 실패 / 3 허용 안 된 명령 / 4 줄 없음
run_app() {
  local app="$1" key="$2" handoff cmd
  handoff="apps/$app/HANDOFF.md"
  [ -f "$handoff" ] || { RUN_OUT="$handoff 없음"; return 4; }
  cmd="$(grep -m1 "$key:" "$handoff" | sed -n 's/.*`\(.*\)`.*/\1/p')"
  [ -z "$cmd" ] && { RUN_OUT="'$key:' 줄 없음"; return 4; }
  RUN_CMD="$cmd"
  # 문서에 적힌 명령을 그대로 실행하므로, 정해진 테스트 도구로 시작하고
  # 명령을 이어 붙이는 기호가 없는 것만 실행한다
  if ! printf '%s' "$cmd" | grep -Eq '^(npx playwright test|npx vitest run|npm test|npm run test|node --test|\./gradlew test|gradlew test|gradle test|\./mvnw test|mvn test|python -m pytest|python3 -m pytest|py -m pytest|pytest|bash tests/[A-Za-z0-9_./-]+\.sh)( [A-Za-z0-9_./=-]+)*$'; then
    RUN_OUT="허용되지 않은 테스트 명령이라 실행하지 않았습니다 (명령: $cmd)
허용: npx playwright test, npx vitest run, npm test, npm run test, node --test, ./gradlew test, gradle test, ./mvnw test, mvn test, (python -m) pytest, bash tests/<파일>.sh (뒤에 옵션만, ; | & \$ 같은 기호 금지)"
    return 3
  fi
  RUN_OUT="$(cd "apps/$app" && bash -c "$cmd" 2>&1)" && return 0
  return 1
}

if [ "$mode" = "app" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
  cd "$root" || exit 1
  app="${2%/}"; app="${app#apps/}"
  key="테스트 실행"; [ "$3" = "백엔드" ] && key="백엔드 테스트"
  run_app "$app" "$key"; rc=$?
  printf '%s\n' "$RUN_OUT"   # 전체 출력: graph.sh가 테스트 개수를 읽는다(Gradle은 테스트마다 한 줄)
  [ $rc -eq 0 ] && exit 0
  exit 1
fi

input="$(cat)"

if [ "$mode" = "commit" ]; then
  # git commit 명령이 아니면 아무것도 하지 않는다
  printf '%s' "$input" | grep -q 'git commit' || exit 0
fi

if [ "$mode" = "stop" ]; then
  # 이미 한 번 멈춰 세웠으면 이번에는 보내 준다 (무한 반복 방지)
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# 커밋되지 않은 변경(스테이지, 수정, 새 파일)이 있는 앱 목록
apps="$(git status --porcelain --untracked-files=all -- apps \
  | sed -E 's/^.. //; s/^.* -> //; s/^"//' \
  | grep -E '^apps/[^/]+/' \
  | cut -d/ -f2 | sort -u)"
[ -z "$apps" ] && exit 0

failed=""
report=""
while IFS= read -r app; do
  [ -f "apps/$app/HANDOFF.md" ] || continue
  key="테스트 실행"
  if [ -f "apps/$app/state.json" ] && [ -f "$G" ]; then
    nodes="$(bash "$G" current "apps/$app" --status </dev/null 2>/dev/null)" || nodes=""   # 깨졌으면 비움 → 테스트 실행 줄
    if [ "$mode" = "stop" ] && printf '%s\n' "$nodes" | grep -Eq '^(bb|bf):진행$'; then
      continue   # 구현 노드 자동 루프(graph-stop.sh)가 같은 검사를 한다
    fi
    if printf '%s\n' "$nodes" | grep -Eq '^(bb|cb):' && grep -q '백엔드 테스트:' "apps/$app/HANDOFF.md"; then
      key="백엔드 테스트"
    fi
  fi
  run_app "$app" "$key"; rc=$?
  case $rc in
    0|4) ;;
    3) failed="$failed $app"; report="$report
--- apps/$app: $RUN_OUT ---" ;;
    *) failed="$failed $app"; report="$report
--- apps/$app $key 실패 (명령: $RUN_CMD) ---
$(printf '%s\n' "$RUN_OUT" | tail -n 30)" ;;
  esac
done <<< "$apps"

[ -z "$failed" ] && exit 0

if [ "$mode" = "commit" ]; then
  echo "[테스트] 커밋을 막았습니다: 테스트가 실패한 앱이 있습니다 ($failed ). 테스트가 실패한 상태로는 커밋하지 않습니다(CLAUDE.md). 실패한 것을 고친 뒤 다시 커밋하세요.$report" >&2
else
  echo "[테스트] 아직 테스트가 실패하는 앱이 있습니다 ($failed ). '다 됐다'고 말하지 마세요. 고칠 수 있으면 계속 고치고, 멈춰야 하면 남은 실패와 이유를 apps/<앱>/docs/NOTES.md에 적고 사용자에게 사실대로 알리세요.$report" >&2
fi
exit 2

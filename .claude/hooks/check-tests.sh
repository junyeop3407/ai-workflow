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
LOCKSH="$(cd "$(dirname "$0")" && pwd)/lock.sh"

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
  # 같은 테스트 환경(포트)은 한 번에 하나 — 두 세션·Stop 훅 둘이 동시에 돌려 "포트 사용 중"으로 서로 깨지 않게.
  # HANDOFF '포트: 8081 5174' 줄의 포트마다 잠금, 없으면 env:port:default 하나에 줄 세움(모르면 안전하게 직렬)
  local ports names="" p rc
  ports="$(grep -m1 '^포트:' "$handoff" | grep -o '[0-9]\{2,5\}')"
  for p in ${ports:-default}; do names="${names:+$names,}env:port:$p"; done
  if [ -f "$LOCKSH" ]; then
    RUN_OUT="$(cd "apps/$app" && bash "$LOCKSH" run "$names" --wait "${TEST_LOCK_WAIT:-1800}" --label "테스트 $app ($key)" -- bash -c "$cmd" 2>&1)"; rc=$?
  else
    RUN_OUT="$(cd "apps/$app" && bash -c "$cmd" 2>&1)"; rc=$?
  fi
  [ $rc -eq 0 ] && return 0
  [ $rc -eq 4 ] && printf '%s' "$RUN_OUT" | grep -q "^잠금 'env:port:" && RUN_OUT="테스트 환경 잠금을 기다리다 멈췄습니다(다른 테스트가 같은 포트를 오래 씀): $RUN_OUT"
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
  # git과 commit 사이에 옵션이 끼어도(git -c … commit, git --git-dir=… commit, git -C … commit) 커밋으로 본다
  printf '%s' "$input" | grep -Eq '(^|[^[:alnum:]_.-])git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+commit([[:space:]]|"|$)' || exit 0
  # 예외(사장 결정 2026-11-23): 임시 브랜치 wip/<앱> 에서만 테스트가 실패한 채로 커밋할 수 있다 —
  # 구현 중에 다른 컴퓨터(집 Windows ↔ 밖 Mac)로 옮기려고. main 등 다른 브랜치는 그대로 막는다.
  # wip를 main에 합칠 때는 guard-git.sh가 --squash를 요구해서, 합친 뒤의 git commit 에서 이 검사가 다시 돈다.
  # 승인된 테스트 잠금 검사(check-approved.sh commit)는 wip에서도 그대로.
  # 예외는 "git commit 하나만 있는 명령"일 때만: 훅은 실행 전 브랜치를 보므로, 이어 붙인 명령(;·&&·||·|·줄바꿈)이나
  # 브랜치를 바꾸는 명령(switch·checkout·reset·update-ref·symbolic-ref·branch·worktree·-C)이 섞이면 예외를 주지 않는다.
  #   더 좁게: 명령 전체가 정확히 `git commit [-a] [-q] -m "<메시지>" [-m "<메시지>"]` 꼴일 때만(앞에 환경 변수·git 전역 옵션
  #   --git-dir·--work-tree·-c 등이 붙으면 다른 저장소를 가리킬 수 있어 예외 없음). 마지막 방어선은 .githooks/pre-push.
  wcmd="$(printf '%s' "$input" | tr '\n' ' ' | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' | sed 's/\\"/"/g; s/"[[:space:]]*,[[:space:]]*"[a-z_]*"[[:space:]]*:.*//; s/"[[:space:]]*}[}[:space:]]*$//')"
  if printf '%s' "$wcmd" | grep -Eq '^[[:space:]]*git[[:space:]]+commit([[:space:]]+(-a|-q|-m[[:space:]]+("[^"`$\\;&|]*"|[^[:space:]"'"'"'`$\\;&|-][^[:space:]"'"'"'`$\\;&|]*)))+[[:space:]]*$' \
     && ! printf '%s' "$wcmd" | grep -Eq '[;&|`]|\$\(|(^|[[:space:]])(switch|checkout|reset|update-ref|symbolic-ref|branch|worktree)([[:space:]]|$)'; then
    case "$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" in
      wip/*) exit 0 ;;
    esac
  fi
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

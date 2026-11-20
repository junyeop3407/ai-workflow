#!/usr/bin/env bash
# 백엔드 테스트 견본 (graph.md bb 노드의 통과 검사) — apps/<앱>/tests/backend.sh 로 복사해 맨 위 변수만 고친다.
# HANDOFF: 백엔드 테스트: `bash tests/backend.sh`   (훅·graph.sh가 앱 폴더에서 실행한다)
# 순서: ① 백엔드 부품 테스트(JUnit) → ② 서버 만들기 → ③ 서버 켜기 → ④ 뜰 때까지 기다림 → ⑤ api.md 예시 확인 → 서버 끄기
# 안전장치 (Windows Git Bash·Mac 둘 다):
#   - 시작 전에 포트가 이미 쓰이고 있으면 바로 멈춘다. 남의 프로세스는 건드리지 않는다.
#   - 실패·중단(Ctrl+C 포함)해도 trap 으로 이 스크립트가 켠 서버만 끈다. 끈 뒤 포트가 닫혔는지 다시 본다.
#   - 서버가 SERVER_WAIT 초 안에 안 뜨면 서버 로그 끝 20줄을 보여 주고 실패한다. (`timeout` 명령은 Mac에 없어서 SECONDS로 잰다)

PORT="${PORT:-8080}"
SERVER_WAIT="${SERVER_WAIT:-60}"
UNIT_TEST="${UNIT_TEST:-./gradlew test}"
BUILD="${BUILD:-./gradlew bootJar -q}"
# 감싸개(gradlew bootRun) 대신 java 를 직접 띄워야 끌 때 java 가 남지 않는다
SERVER_CMD="${SERVER_CMD:-java -jar build/libs/app.jar --server.port=$PORT}"
API_MD="${API_MD:-docs/api.md}"
LOG="${LOG:-build/server.log}"
API_CHECK="${API_CHECK:-$(git rev-parse --show-toplevel)/.claude/skills/build-app/api-check.sh}"

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }
pid=""
stop_server() {
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null
  local i=0
  while port_open && [ $i -lt 3 ]; do sleep 1; i=$((i+1)); done
  if port_open; then
    kill -9 "$pid" 2>/dev/null
    # Windows: 이 스크립트가 켠 프로세스만 강제로 끈다
    [ -r "/proc/$pid/winpid" ] && command -v taskkill >/dev/null 2>&1 && taskkill //F //T //PID "$(cat "/proc/$pid/winpid")" >/dev/null 2>&1
    sleep 1
  fi
  if port_open; then echo "서버가 남았을 수 있음: 포트 $PORT (이 스크립트가 켠 pid $pid). 직접 확인해 끄세요." >&2; return 1; fi
  pid=""
}
cleanup() { local rc=$?; trap - EXIT INT TERM; stop_server || rc=1; exit $rc; }

# 0. 포트가 이미 쓰이고 있으면 아무것도 켜지 않고 멈춘다
if port_open; then
  echo "포트 $PORT 사용 중 — 남은 서버를 끄세요. (이 스크립트는 남의 프로세스를 끄지 않습니다)" >&2
  exit 1
fi
trap cleanup EXIT
trap 'exit 130' INT TERM

# ① 부품 테스트 ② 서버 만들기
echo "① 백엔드 부품 테스트: $UNIT_TEST"
eval "$UNIT_TEST" || { echo "백엔드 부품 테스트 실패" >&2; exit 1; }
echo "② 서버 만들기: $BUILD"
eval "$BUILD" || { echo "서버 만들기 실패" >&2; exit 1; }

# ③ 서버 켜기 (exec 로 바꿔 $! 가 서버 자체가 되게)
mkdir -p "$(dirname "$LOG")"
( eval "exec $SERVER_CMD" ) > "$LOG" 2>&1 &
pid=$!
echo "③ 서버 켬 (pid $pid, 포트 $PORT)"

# ④ 뜰 때까지 기다림
SECONDS=0
until port_open; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "서버가 뜨기 전에 꺼졌습니다. 로그 끝 20줄:" >&2; tail -n 20 "$LOG" >&2; pid=""; exit 1
  fi
  if [ "$SECONDS" -ge "$SERVER_WAIT" ]; then
    echo "서버가 ${SERVER_WAIT}초 안에 뜨지 않았습니다. 로그 끝 20줄:" >&2; tail -n 20 "$LOG" >&2; exit 1
  fi
  sleep 1
done
echo "④ 서버 뜸 (${SECONDS}초)"

# ⑤ api.md 예시 확인
bash "$API_CHECK" "$API_MD" "http://localhost:$PORT"

#!/usr/bin/env bash
# 훅 시험: 임시 폴더에 가짜 git 저장소 + 가짜 앱을 만들고, 훅마다 가짜 입력(JSON)으로
# "막아야 할 경우 / 통과해야 할 경우"를 돌려 표로 보여 준다. 실제 저장소는 건드리지 않는다.
# 사용: bash .claude/hooks/test-hooks.sh            (훅 동작)
#       bash .claude/hooks/test-hooks.sh --settings (+ settings.json 등록 확인)
# 결과: 기대와 다른 줄이 하나라도 있으면 exit 1.

src="$(git rev-parse --show-toplevel)" || exit 1
H="$src/.claude/hooks"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q . && git config user.email t@example.com && git config user.name tester && git config core.autocrlf false

fails=0
rows=""
row() { # 경우, 기대, 실제
  local mark="✅"
  if [ "$2" != "기록" ] && [ "$2" != "$3" ]; then mark="❌"; fails=$((fails+1)); fi
  rows="$rows
| $(printf '%s' "$1" | sed 's/|/\\|/g') | $2 | $3 | $mark |"
}
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
bash_json_raw() { printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"x"}}' "$1"; }  # JSON 이스케이프(\n 등)를 그대로 넣음
bash_json()  { printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"x"}}' "$(jesc "$1")"; }
write_json() { printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$(jesc "$1")" "$(jesc "$2")"; }
edit_json()  { printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"%s"}}' "$(jesc "$1")" "$(jesc "$2")"; }
agent_write_json() { printf '{"session_id":"t","hook_event_name":"PreToolUse","agent_id":"a1","agent_type":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1" "$(jesc "$2")"; }
stop_json()  { printf '{"session_id":"t","hook_event_name":"Stop","stop_hook_active":%s}' "$1"; }

# 훅 실행 → 막힘(exit 2) / ask / 통과 / 기타
run() { # 입력JSON, 훅, [인자]
  local out code
  out="$(printf '%s' "$1" | bash "$H/$2" $3 2>"$tmp/.err")"; code=$?
  if [ $code -eq 2 ]; then echo "막힘"
  elif [ $code -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then echo "ask"
  elif [ $code -eq 0 ]; then echo "통과"
  else echo "exit $code"; fi
}
# 훅 출력(stdout) 그대로
run_out() { printf '%s' "$1" | bash "$H/$2" $3 2>/dev/null; }

# ---- 가짜 앱: 테스트는 아직 커밋하지 않은 상태(3~4단계) ----
mkdir -p apps/demo/tests/fixtures apps/demo/src .claude/hooks docs
printf '# demo\n현재 단계: 4 (구현)\n' > apps/demo/HANDOFF.md
git add -A && git commit -qm init
printf 'def test_total():\n    assert total([1,2]) == 3\n' > apps/demo/tests/test_main.py
printf 'import pytest\n' > apps/demo/tests/conftest.py
printf 'a,b\n' > apps/demo/tests/fixtures/in.csv
cp "$H/approve-tests.sh" .claude/hooks/approve-tests.sh
bash "$H/approve-tests.sh" apps/demo >/dev/null   # 사장이 ! 로 실행한 것과 같음
T="$tmp/apps/demo/tests/test_main.py"

# ---- 1. 승인된 테스트 잠금 (protect-tests.sh) ----
row "커밋 안 된 승인 테스트를 Edit" ask "$(run "$(edit_json "$T" "b")" protect-tests.sh)"
row "같은 파일, Windows 경로(C:\\...\\)로 Edit" ask "$(run "$(edit_json 'C:\work\apps\demo\tests\test_main.py' "b")" protect-tests.sh)"
row ".approved 자체를 Edit" ask "$(run "$(edit_json "$tmp/apps/demo/tests/.approved" "x")" protect-tests.sh)"
row "승인 안 된 새 테스트 Write" 통과 "$(run "$(write_json "$tmp/apps/demo/tests/test_new.py" "x")" protect-tests.sh)"
row "준비 코드(conftest.py) Edit" 통과 "$(run "$(edit_json "$tmp/apps/demo/tests/conftest.py" "x")" protect-tests.sh)"
row "앱 코드 Edit" 통과 "$(run "$(edit_json "$tmp/apps/demo/src/app.js" "x")" protect-tests.sh)"
row "Claude가 Bash로 approve-tests.sh 실행" 막힘 "$(run "$(bash_json "bash .claude/hooks/approve-tests.sh apps/demo")" protect-tests.sh)"
row "PowerShell로 approve-tests.sh 실행" 막힘 "$(run "$(bash_json "bash .claude/hooks/approve-tests.sh apps/demo" | sed 's/"Bash"/"PowerShell"/')" protect-tests.sh)"
row "이름 바꾼 복사본: cp approve-tests.sh x.sh; bash x.sh" 막힘 "$(run "$(bash_json "cp .claude/hooks/approve-tests.sh x.sh; bash x.sh apps/demo")" protect-tests.sh)"
row "(남은 위험) 복사본이 이미 있을 때 bash x.sh apps/demo" 기록 "$(run "$(bash_json "bash x.sh apps/demo")" protect-tests.sh | sed 's/^통과$/통과 = 못 막음/')"
row "Write로 apps/x/tools/a.sh 에 .approved 쓰는 스크립트" 막힘 "$(run "$(write_json "$tmp/apps/demo/tools/a.sh" "sha256sum t > tests/.approved")" protect-tests.sh)"
row "Edit로 .py 에 approve-tests 넣기" 막힘 "$(run "$(edit_json "$tmp/apps/demo/tools/b.py" "os.system('bash approve-tests.sh')")" protect-tests.sh)"
row "build-app SKILL.md에 .approved 문장 쓰기" 통과 "$(run "$(write_json "$tmp/.claude/skills/build-app/SKILL.md" "tests/.approved 는 사장만")" protect-tests.sh)"
row ".claude/hooks/ 안 훅에 .approved 쓰기" 통과 "$(run "$(write_json "$tmp/.claude/hooks/check-approved.sh" "apps/*/tests/.approved")" protect-tests.sh)"
row "읽기: git log -p -- '*/.approved'" 통과 "$(run "$(bash_json "git log -p -- '*/.approved'")" protect-tests.sh)"
row "읽기: cat apps/demo/tests/.approved" 통과 "$(run "$(bash_json "cat apps/demo/tests/.approved")" protect-tests.sh)"
row "읽기: git diff --stat … .approved | grep test 2>&1" 통과 "$(run "$(bash_json "git diff --stat -- apps/demo/tests/.approved | grep test 2>&1")" protect-tests.sh)"
row "쓰기: cat x > apps/demo/tests/.approved" 막힘 "$(run "$(bash_json "cat x > apps/demo/tests/.approved")" protect-tests.sh)"
row "쓰기: cat x | tee apps/demo/tests/.approved" 막힘 "$(run "$(bash_json "cat x | tee apps/demo/tests/.approved")" protect-tests.sh)"
row "쓰기: sed -i … .approved" 막힘 "$(run "$(bash_json "sed -i s/a/b/ apps/demo/tests/.approved")" protect-tests.sh)"
row "읽기처럼 보이고 뒤에 rm: cat .approved && rm …" 막힘 "$(run "$(bash_json "cat apps/demo/tests/.approved && rm apps/demo/tests/.approved")" protect-tests.sh)"
row "관계없는 Bash(ls)" 통과 "$(run "$(bash_json "ls apps")" protect-tests.sh)"
row "git add apps/x/tests/.approved" 통과 "$(run "$(bash_json "git add apps/x/tests/.approved")" protect-tests.sh)"
row "git add -A -- apps/x/tests/.approved apps/x/src" 통과 "$(run "$(bash_json "git add -A -- apps/x/tests/.approved apps/x/src")" protect-tests.sh)"
row "git commit -m \"테스트 잠금(.approved) 갱신\"" 통과 "$(run "$(bash_json "git commit -m \"테스트 잠금(.approved) 갱신\"")" protect-tests.sh)"
row "git commit -m '…approve-tests; > 같은 글자…'" 통과 "$(run "$(bash_json "git commit -m 'approve-tests 안내; a > b 문장'")" protect-tests.sh)"
row "git add a.txt && git commit -m \"잠금(.approved)\"" 통과 "$(run "$(bash_json "git add a.txt && git commit -m \"잠금(.approved)\"")" protect-tests.sh)"
row "git add a && bash .claude/hooks/approve-tests.sh apps/x" 막힘 "$(run "$(bash_json "git add a && bash .claude/hooks/approve-tests.sh apps/x")" protect-tests.sh)"
row "git commit -m \"x\" ; rm apps/x/tests/.approved" 막힘 "$(run "$(bash_json "git commit -m \"x\" ; rm apps/x/tests/.approved")" protect-tests.sh)"
row "git commit -m \"\$(bash approve-tests.sh)\"" 막힘 "$(run "$(bash_json "git commit -m \"\$(bash approve-tests.sh)\"")" protect-tests.sh)"
row "cp x apps/x/tests/.approved / mv x …/.approved" 막힘 "$(run "$(bash_json "cp x apps/x/tests/.approved")" protect-tests.sh)"
row "(우회) git log '-m \"' ; rm …/.approved ; git log '\"'" 막힘 "$(run "$(bash_json "git log '-m \"' ; rm apps/x/tests/.approved ; git log '\"'")" protect-tests.sh)"
row "(우회) git commit -m \"a\\\" ; rm …/.approved\" (따옴표 안 글자)" 통과 "$(run "$(bash_json "git commit -m \"a\\\" ; rm apps/x/tests/.approved\"")" protect-tests.sh)"
row "(우회) 줄바꿈으로 붙인 rm (cat …\\nrm …/.approved)" 막힘 "$(run "$(bash_json_raw 'cat apps/x/tests/.approved\nrm apps/x/tests/.approved')" protect-tests.sh)"
row "(우회) \\; 로 숨긴 것: cat a\\; rm …/.approved" 막힘 "$(run "$(bash_json "cat a\\; rm apps/x/tests/.approved")" protect-tests.sh)"
row "(우회) \$'…' 따옴표" 막힘 "$(run "$(bash_json "git log \$'x\\'' ; rm apps/x/tests/.approved")" protect-tests.sh)"
row "(우회) 닫히지 않은 따옴표" 막힘 "$(run "$(bash_json "git commit -m \"x ; rm apps/x/tests/.approved")" protect-tests.sh)"
row "(우회) 따옴표 안 --output: git diff '--output=…/.approved'" 막힘 "$(run "$(bash_json "git diff '--output=apps/x/tests/.approved'")" protect-tests.sh)"
row "(우회) JSON 잘림: cat … ; git log \",\"a\": ; rm …/.approved" 막힘 "$(run "$(bash_json "cat apps/x/tests/.approved ; git log \",\"a\": ; rm apps/x/tests/.approved")" protect-tests.sh)"
bs="$(printf '\134')"   # 역슬래시 (파일 편집 도구가 유니코드 이스케이프를 풀어 버리지 않게 실행할 때 만듦)
row "(우회) 유니코드 이스케이프(u0027)로 따옴표 숨기기" 막힘 "$(run "$(bash_json_raw "git log ${bs}u0027x${bs}u0027 ; cat apps/x/tests/.approved")" protect-tests.sh)"
row "git add .approved > out.txt (리디렉션)" 막힘 "$(run "$(bash_json "git add apps/x/tests/.approved > out.txt")" protect-tests.sh)"

# ---- 1. 해시 검사 (check-approved.sh) ----
row "변경 없음: git commit" 통과 "$(run "$(bash_json "git commit -m x")" check-approved.sh commit)"
row "변경 없음: Stop" 통과 "$(run "$(stop_json false)" check-approved.sh stop)"
cp "$T" "$tmp/.bak"
sed -i 's/== 3/== 4/' "$T"   # Bash sed -i 로 승인 테스트를 고침 (Edit 훅을 거치지 않음)
row "Bash sed -i로 승인 테스트 수정 후 git commit" 막힘 "$(run "$(bash_json "git add -A && git commit -m x")" check-approved.sh commit)"
row "같은 상태에서 Stop" 막힘 "$(run "$(stop_json false)" check-approved.sh stop)"
row "같은 상태, Stop 두 번째(stop_hook_active)" 통과 "$(run "$(stop_json true)" check-approved.sh stop)"
row "같은 상태, commit 아닌 Bash(ls)" 통과 "$(run "$(bash_json "ls")" check-approved.sh commit)"
c="git add apps/demo/tests/.approved && git commit -m \"잠금(.approved) 갱신\""
row "바뀐 상태에서 '.approved add + commit -m' — protect는 통과" 통과 "$(run "$(bash_json "$c")" protect-tests.sh)"
row "→ 같은 명령을 해시 검사(commit)가 막음" 막힘 "$(run "$(bash_json "$c")" check-approved.sh commit)"
cp "$tmp/.bak" "$T"
rm "$T"
row "승인 테스트를 rm 후 git commit" 막힘 "$(run "$(bash_json "git commit -am x")" check-approved.sh commit)"
cp "$tmp/.bak" "$T"
sed -i 's/$/\r/' "$T"         # 줄바꿈만 CRLF로 바뀜 (다른 컴퓨터)
row "줄바꿈만 CRLF로 바뀜 → git commit" 통과 "$(run "$(bash_json "git commit -m x")" check-approved.sh commit)"
cp "$tmp/.bak" "$T"

# ---- 1. 레드팀 표시 (flag-redteam.sh) ----
flag="$tmp/apps/demo/.redteam-needed"
rm -f "$flag"
printf 'class A{}\n' > apps/demo/src/Helper.java
cp apps/demo/src/Helper.java apps/demo/src/AuthController.java   # Bash cp 로 민감 파일 생성
git add apps/demo/src/AuthController.java
run_out "$(bash_json "git commit -m x")" flag-redteam.sh commit >/dev/null
row "cp로 AuthController 만들고 스테이지 → commit" "표시 생김" "$([ -f "$flag" ] && echo "표시 생김" || echo "표시 없음")"
git reset -q apps/demo/src/AuthController.java; rm -f "$flag"
printf 'a{}\n' > apps/demo/src/style.css; git add apps/demo/src/style.css
run_out "$(bash_json "git commit -m x")" flag-redteam.sh commit >/dev/null
row "CSS만 스테이지 → commit" "표시 없음" "$([ -f "$flag" ] && echo "표시 생김" || echo "표시 없음")"
git reset -q; rm -f "$flag"
run_out "$(bash_json "git add -A && git commit -m x")" flag-redteam.sh commit >/dev/null
row "스테이지 전 민감 파일 + 'git add -A && git commit'" "표시 생김" "$([ -f "$flag" ] && echo "표시 생김" || echo "표시 없음")"
rm -f "$flag"
o="$(run_out "$(edit_json "$tmp/apps/demo/src/PaymentService.java" "x" | sed 's/PreToolUse/PostToolUse/')" flag-redteam.sh)"
row "(기존) Edit로 PaymentService 수정 → PostToolUse" "표시 생김" "$([ -f "$flag" ] && printf '%s' "$o" | grep -q additionalContext && echo "표시 생김" || echo "표시 없음")"
rm -f "$flag" apps/demo/src/AuthController.java apps/demo/src/style.css apps/demo/src/Helper.java

# ---- 기존 훅 동작 그대로 (guard-git.sh, check-tests.sh) ----
row "(기존) guard-git: git push --force" 막힘 "$(run "$(bash_json "git push --force origin main")" guard-git.sh)"
row "(기존) guard-git: 깨끗한 commit" 통과 "$(run "$(bash_json "git commit -m x")" guard-git.sh)"
mkdir -p .claude/agent-memory/red-team
key="AKIA$(printf 'Q%.0s' $(seq 16))"
printf -- '- 자주 뚫리는 곳: 토큰 검사\n- %s\n' "$key" > .claude/agent-memory/red-team/MEMORY.md
git add .claude/agent-memory/red-team/MEMORY.md
row "agent-memory 파일에 가짜 키 패턴 넣고 commit" 막힘 "$(run "$(bash_json "git commit -m x")" guard-git.sh)"
git reset -q; rm -rf .claude/agent-memory
mkdir -p apps/demo2/tests
printf '# demo2\n현재 단계: 4\n테스트 실행: `bash tests/run.sh`\n' > apps/demo2/HANDOFF.md
printf 'exit 1\n' > apps/demo2/tests/run.sh
row "(기존) check-tests: 테스트 실패 앱 commit" 막힘 "$(run "$(bash_json "git commit -m x")" check-tests.sh commit)"
printf 'exit 0\n' > apps/demo2/tests/run.sh
row "(기존) check-tests: 테스트 통과 앱 commit" 통과 "$(run "$(bash_json "git commit -m x")" check-tests.sh commit)"
rm -rf apps/demo2

# ---- check-tests: 그래프 현재 노드에 따라 검사 줄 고르기 (bb·cb = 백엔드 테스트, 그 밖 = 테스트 실행) ----
G="$src/.claude/skills/build-app/graph.sh"
mkdir -p apps/demo3/tests
printf '# demo3\n현재 단계: 4\n테스트 실행: `bash tests/run.sh`\n백엔드 테스트: `bash tests/backend.sh`\n' > apps/demo3/HANDOFF.md
printf 'exit 1\n' > apps/demo3/tests/run.sh   # 승인된 Playwright 흉내: 실패(프론트 아직)
bash "$G" init apps/demo3 >/dev/null 2>&1
cp apps/demo3/state.json "$tmp/.st3"
at_node() { # 시험용: 현재 노드를 $1, 상태를 $2 로 바꾼 가짜 state.json
  cp "$tmp/.st3" apps/demo3/state.json
  sed -i "s/\"current\": \[[^]]*\]/\"current\": [\"$1\"]/; s/\"req\": {\"status\": \"진행\"/\"req\": {\"status\": \"통과\"/; s/\"$1\": {\"status\": \"[^\"]*\"/\"$1\": {\"status\": \"$2\"/" apps/demo3/state.json
}
printf 'exit 0\n' > apps/demo3/tests/backend.sh
at_node bb 진행
row "bb + 백엔드 테스트 통과 + Playwright 실패 → commit" 통과 "$(run "$(bash_json "git commit -m x")" check-tests.sh commit)"
printf 'exit 1\n' > apps/demo3/tests/backend.sh
row "bb + 백엔드 테스트 실패 → commit" 막힘 "$(run "$(bash_json "git commit -m x")" check-tests.sh commit)"
at_node bf 진행
row "bf + Playwright 실패 → commit (bf부터는 테스트 실행 줄)" 막힘 "$(run "$(bash_json "git commit -m x")" check-tests.sh commit)"
printf '{\n  "version": 1,\n' > apps/demo3/state.json
row "state.json 깨짐 + Playwright 실패 → commit" 막힘 "$(run "$(bash_json "git commit -m x")" check-tests.sh commit)"
at_node bb 진행
row "stop: bb 진행 + 백엔드 실패 → 건너뜀(graph-stop 자동 루프가 맡음)" 통과 "$(run "$(stop_json false)" check-tests.sh stop)"
at_node bf 진행
row "stop: bf 진행 + Playwright 실패 → 건너뜀(graph-stop이 맡음)" 통과 "$(run "$(stop_json false)" check-tests.sh stop)"
printf 'exit 0\n' > apps/demo3/tests/backend.sh
at_node cb 진행
row "stop: cb + 백엔드 통과 + Playwright 실패" 통과 "$(run "$(stop_json false)" check-tests.sh stop)"
printf 'exit 1\n' > apps/demo3/tests/backend.sh
row "stop: cb + 백엔드 실패" 막힘 "$(run "$(stop_json false)" check-tests.sh stop)"
at_node tr 진행
row "stop: tr + Playwright 실패" 막힘 "$(run "$(stop_json false)" check-tests.sh stop)"
printf '{\n' > apps/demo3/state.json
row "stop: state.json 깨짐 + Playwright 실패" 막힘 "$(run "$(stop_json false)" check-tests.sh stop)"
rm -rf apps/demo3

# ---- 5. 에이전트 메모리 (agent-memory-only.sh) ----
row "red-team이 자기 메모리 폴더에 Write" 통과 "$(run "$(agent_write_json red-team "$tmp/.claude/agent-memory/red-team/MEMORY.md")" agent-memory-only.sh)"
row "red-team이 앱 코드에 Write" 막힘 "$(run "$(agent_write_json red-team "$tmp/apps/demo/src/app.js")" agent-memory-only.sh)"
row "qa-reviewer가 red-team 메모리에 Write" 막힘 "$(run "$(agent_write_json qa-reviewer "$tmp/.claude/agent-memory/red-team/MEMORY.md")" agent-memory-only.sh)"
row "red-team이 ../ 로 빠져나가기" 막힘 "$(run "$(agent_write_json red-team "$tmp/.claude/agent-memory/red-team/../../hooks/x.sh")" agent-memory-only.sh)"
row "red-team이 Windows 경로로 메모리 Write" 통과 "$(run "$(agent_write_json red-team 'C:\work\.claude\agent-memory\red-team\MEMORY.md')" agent-memory-only.sh)"
row "frontmatter 방식(인자 qa-reviewer, agent_type 없음) 앱 코드" 막힘 "$(run "$(write_json "$tmp/apps/demo/src/app.js" "x")" agent-memory-only.sh qa-reviewer)"
row "메인 대화(agent_type 없음)가 앱 코드 Write" 통과 "$(run "$(write_json "$tmp/apps/demo/src/app.js" "x")" agent-memory-only.sh)"
row "다른 에이전트(test-runner)가 Write" 통과 "$(run "$(agent_write_json test-runner "$tmp/apps/demo/src/app.js")" agent-memory-only.sh)"

# ---- 5-1. 개발팀 파일 경계 (team-files.sh) ----
row "backend-dev가 서버 코드(src/main/java) Write" 통과 "$(run "$(agent_write_json backend-dev "$tmp/apps/demo/src/main/java/A.java")" team-files.sh)"
row "backend-dev가 build.gradle Write" 통과 "$(run "$(agent_write_json backend-dev "$tmp/apps/demo/build.gradle")" team-files.sh)"
row "backend-dev가 화면 코드 Write" 막힘 "$(run "$(agent_write_json backend-dev "$tmp/apps/demo/src/App.tsx")" team-files.sh)"
row "backend-dev가 구조 검사 테스트(src/test) Write" 막힘 "$(run "$(agent_write_json backend-dev "$tmp/apps/demo/src/test/java/ArchitectureTest.java")" team-files.sh)"
row "frontend-dev가 화면 코드 Write" 통과 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/src/App.tsx")" team-files.sh)"
winroot="$(cygpath -w "$tmp" 2>/dev/null || printf '%s' "$tmp")"
row "frontend-dev가 Windows 경로로 화면 코드 Write" 통과 "$(run "$(agent_write_json frontend-dev "$winroot\\apps\\demo\\src\\App.tsx")" team-files.sh)"
row "frontend-dev가 저장소 밖 다른 apps/ 경로 Write" 막힘 "$(run "$(agent_write_json frontend-dev '/elsewhere/apps/demo/src/App.tsx')" team-files.sh)"
row "backend-dev가 화면 폴더 안 중첩 apps/../src/main/java Write" 막힘 "$(run "$(agent_write_json backend-dev "$tmp/apps/demo/src/apps/y/src/main/java/A.java")" team-files.sh)"
row "frontend-dev가 대문자 Src/Main/Java Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/Src/Main/Java/A.java")" team-files.sh)"
row "frontend-dev가 // 섞은 서버 경로 Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo//src/main//java/A.java")" team-files.sh)"
row "frontend-dev가 ./ 섞은 tests 경로 Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/./tests/a.ts")" team-files.sh)"
row "frontend-dev가 package.json Write (통합 몫)" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/package.json")" team-files.sh)"
row "frontend-dev가 vite.config Write (테스트 설정일 수 있음)" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/vite.config.ts")" team-files.sh)"
row "frontend-dev가 src 안 테스트 파일(App.test.tsx) Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/src/App.test.tsx")" team-files.sh)"
row "frontend-dev가 앱 .gitignore Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/.gitignore")" team-files.sh)"
row "frontend-dev가 목록에 없는 파일(Makefile) Write — 기본 거부" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/Makefile")" team-files.sh)"
# check 모드: mark 뒤 Bash로 바꾼 것까지 저장소 전체에서 확인
bash "$H/team-files.sh" mark >/dev/null
printf 'x\n' > apps/demo/src/ok.tsx
row "check: mark 뒤 화면 파일만 바뀜" "exit 0" "$(bash "$H/team-files.sh" check apps/demo frontend-dev >/dev/null 2>&1; echo "exit $?")"
printf 'x\n' > outside-team.txt
row "check: 앱 폴더 밖 파일을 Bash로 만듦" "exit 1" "$(bash "$H/team-files.sh" check apps/demo frontend-dev >/dev/null 2>&1; echo "exit $?")"
rm -f outside-team.txt apps/demo/src/ok.tsx
row "frontend-dev가 서버 코드 Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/src/main/java/A.java")" team-files.sh)"
row "frontend-dev가 tests/ Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/tests/a.spec.ts")" team-files.sh)"
row "frontend-dev가 docs/api.md Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/docs/api.md")" team-files.sh)"
row "frontend-dev가 playwright.config Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/playwright.config.ts")" team-files.sh)"
row "frontend-dev가 state.json Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/state.json")" team-files.sh)"
row "frontend-dev가 앱 밖(.claude/hooks) Write" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/.claude/hooks/x.sh")" team-files.sh)"
row "frontend-dev가 ../ 로 빠져나가기" 막힘 "$(run "$(agent_write_json frontend-dev "$tmp/apps/demo/src/../../x/tests/a.ts")" team-files.sh)"
row "frontmatter 방식(인자 backend-dev, agent_type 없음) 화면 코드" 막힘 "$(run "$(write_json "$tmp/apps/demo/src/App.tsx" "x")" team-files.sh backend-dev)"
row "메인 대화(agent_type 없음)가 서버 코드 Write" 통과 "$(run "$(write_json "$tmp/apps/demo/src/main/java/A.java" "x")" team-files.sh)"
row "다른 에이전트(qa-reviewer)는 이 훅이 관여 안 함" 통과 "$(run "$(agent_write_json qa-reviewer "$tmp/apps/demo/src/App.tsx")" team-files.sh)"

# ---- 6. 세션 시작 (session-start.sh) ----
ss() { printf '{"session_id":"t","hook_event_name":"SessionStart","source":"%s"}' "$1"; }
old="$(date -d '-10 days' +%Y-%m-%d 2>/dev/null || date -v-10d +%Y-%m-%d)"
echo "$old" > docs/last-weekly-review.txt
row "주간 회고 10일 지남, startup" "묻기" "$(run_out "$(ss startup)" session-start.sh | grep -q 'weekly-review' && echo 묻기 || echo 안 물음)"
row "주간 회고 10일 지남, resume" "안 물음" "$(run_out "$(ss resume)" session-start.sh | grep -q 'weekly-review' && echo 묻기 || echo 안 물음)"
date +%Y-%m-%d > docs/last-weekly-review.txt
row "주간 회고 오늘 함, startup" "안 물음" "$(run_out "$(ss startup)" session-start.sh | grep -q 'weekly-review' && echo 묻기 || echo 안 물음)"
printf '# demo\n현재 단계: 4 (구현)\n테스트 실행: `bash tests/run.sh`\n' > apps/demo/HANDOFF.md
row "진행 중인 앱 있음 → test-runner 점검 알림" "알림" "$(run_out "$(ss startup)" session-start.sh | grep -q 'demo' && echo 알림 || echo 없음)"

# ---- 그래프 훅 (graph-prompt.sh, graph-stop.sh, guard-state.sh, session-start 그래프 줄) ----
G="$src/.claude/skills/build-app/graph.sh"
gd="$(git rev-parse --git-dir)"
rm -rf apps/demo apps/demo3; date +%Y-%m-%d > docs/last-weekly-review.txt
row "SessionStart: 진행 중 앱 없음 → 그래프 줄 없음" "없음" "$(run_out "$(ss startup)" session-start.sh | grep -q '그래프' && echo 있음 || echo 없음)"
mkg() { # 앱 현재노드 상태 — 시험용 가짜 state
  rm -rf "apps/$1"; mkdir -p "apps/$1/src" "apps/$1/tests"
  printf '# %s\n현재 단계: 4\n테스트 실행: `bash tests/run.sh`\n' "$1" > "apps/$1/HANDOFF.md"; printf 'exit 0\n' > "apps/$1/tests/run.sh"
  bash "$G" init "apps/$1" >/dev/null 2>&1
  sed -i -E '/^    "/ s/"status": "[^"]*"/"status": "통과"/; s/^(    "done": \{"status": )"통과"/\1"대기"/' "apps/$1/state.json"
  sed -i -E "s/\"current\": \[[^]]*\]/\"current\": [\"$2\"]/; s/^(    \"$2\": \{\"status\": )\"[^\"]*\"/\1\"$3\"/" "apps/$1/state.json"
}
mkg shop ok-req 사장대기
row "SessionStart(startup): 진행 중 앱 → 그래프 줄" "있음" "$(run_out "$(ss startup)" session-start.sh | grep -q '그래프 shop' && echo 있음 || echo 없음)"
row "SessionStart(compact): 그래프 줄은 다시 넣음" "있음" "$(run_out "$(ss compact)" session-start.sh | grep -q '그래프 shop' && echo 있음 || echo 없음)"
row "SessionStart(resume): 주간 회고·test-runner 점검은 안 넣음" "없음" "$(run_out "$(ss resume)" session-start.sh | grep -qE 'weekly-review|test-runner' && echo 있음 || echo 없음)"
row "SessionStart 출력이 올바른 JSON 모양(따옴표 안 깨짐)" "정상" "$(run_out "$(ss startup)" session-start.sh | awk '{ n=gsub(/"/,"\"") } END { print (n%2==0 ? "정상" : "깨짐") }')"
up() { printf '{"session_id":"t","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"; }
row "UserPromptSubmit: 앱 작업(이어서 해 줘) → 현재 노드 한 줄" "있음" "$(run_out "$(up "shop 앱 이어서 해 줘")" graph-prompt.sh | grep -q 'ok-req' && echo 있음 || echo 없음)"
row "→ 앱 작업 턴 표시(.git/graph-turn) 생김" "있음" "$([ -f "$gd/graph-turn" ] && echo 있음 || echo 없음)"
row "UserPromptSubmit: ★ 대기 중 짧은 답(OK)도 앱 작업" "있음" "$(run_out "$(up "OK")" graph-prompt.sh | grep -q 'ok-req' && echo 있음 || echo 없음)"
row "UserPromptSubmit: 잡담 → 아무것도 안 넣음" "없음" "$(o="$(run_out "$(up "오늘 날씨가 참 좋은 것 같은데 점심은 무엇을 먹으면 좋을지 추천해 주세요")" graph-prompt.sh)"; [ -z "$o" ] && echo 없음 || echo 있음)"
row "→ 잡담이면 앱 작업 턴 표시 지움" "없음" "$([ -f "$gd/graph-turn" ] && echo 있음 || echo 없음)"
row "UserPromptSubmit: 메시지는 절대 안 막음(exit 0)" "통과" "$(run "$(up "앱 만들어 줘")" graph-prompt.sh)"
gst() { run "$(stop_json "${1:-false}")" graph-stop.sh; }
echo turn > "$gd/graph-turn"
row "Stop ①: ★ 노드 사장대기 → 정당한 멈춤" 통과 "$(gst)"
mkg shop qa 사장보고;  row "Stop ②: 사장보고 → 통과" 통과 "$(gst)"
mkg shop cx 도구없음;  row "Stop ③: 도구없음(Codex 미설치) → 통과" 통과 "$(gst)"
mkg shop ex 사장대기;  row "Stop ④: 탐색 사용량 2배 초과(ex 사장대기) → 통과" 통과 "$(gst)"
mkg shop lock 사장대기; row "Stop ⑤: 다시 잠그기 대기(lock 사장대기) → 통과" 통과 "$(gst)"
mkg shop qa 진행; rm -f "$gd"/graph-stop-*
row "Stop 부당: 진행 노드(qa)를 두고 멈춤 → 막힘" 막힘 "$(gst)"
row "Stop 부당 2번째(stop_hook_active여도 같은 상태면) → 막힘" 막힘 "$(gst true)"
row "Stop 부당 3번째 → 사장 보고로 바꾸고 막힘(보고하게)" 막힘 "$(gst true)"
row "→ qa 상태 = 사장보고, 다음 Stop은 통과" "사장보고 통과" "$(bash "$G" get apps/shop status qa) $(gst true)"
rm -f "$gd/graph-turn"; mkg shop qa 진행; touch -d '-1 hour' apps/shop/src/* 2>/dev/null
row "Stop: 잡담 턴(표시 없음)·코드 안 바뀜 → 진행 노드여도 통과" 통과 "$(gst)"
mkg shop ok-ui 사장대기; sleep 1; echo 'x' > apps/shop/src/app.js
row "Stop: ★ 대기 중 앱 코드가 state.json보다 새로움 → 한 번 막힘" 막힘 "$(gst)"
row "→ 같은 상태 stop_hook_active → 통과" 통과 "$(gst true)"
mkg shop ok-ui 사장대기; rm -f apps/shop/src/app.js; touch -d '-1 hour' "apps/shop/state.json"; touch apps/shop/tests/run.sh
row "(기록) git pull 흉내: ★ 대기 + 파일 시각만 새것으로(touch)" 기록 "$(gst) (시각 비교라 한 번 멈춤 — 사장 결정대로 유지)"
row "→ 같은 상황 두 번째(stop_hook_active)" 통과 "$(gst true)"
echo turn > "$gd/graph-turn"; mkg shop bf 진행; printf 'echo "FAILED 담기"; exit 1\n' > apps/shop/tests/run.sh
row "Stop: bf 진행 + 테스트 실패 → 자동 루프가 막음" 막힘 "$(gst true)"
row "→ 회차 state.json에 1" 1 "$(sed -n 's/.*"bf": {"status": "[^"]*", "retries": [0-9]*, "boss_fixes": [0-9]*, "rounds": \([0-9]*\).*/\1/p' apps/shop/state.json)"
printf '{\n' > apps/shop/state.json
row "Stop: 깨진 state.json → 한 번 알림(막힘)" 막힘 "$(gst)"
row "→ stop_hook_active면 통과" 통과 "$(gst true)"
rm -rf apps/shop; mkdir -p apps/nostate; echo x > apps/nostate/a.js
row "Stop: 앱 파일은 바뀌었는데 state.json 없음 → 한 번 알림" 막힘 "$(gst)"
rm -rf apps/nostate "$gd/graph-turn"
row "guard-state: Edit로 apps/x/state.json → 막힘" 막힘 "$(run "$(edit_json "$tmp/apps/x/state.json" "x")" guard-state.sh)"
row "guard-state: Windows 경로로 Write → 막힘" 막힘 "$(run "$(write_json 'C:\work\apps\x\state.json' "x")" guard-state.sh)"
row "guard-state: 다른 json(Edit package.json) → 통과" 통과 "$(run "$(edit_json "$tmp/apps/x/package.json" "x")" guard-state.sh)"

# ---- settings.json 등록 확인 (--settings) ----
if [ "$1" = "--settings" ]; then
  S="$src/.claude/settings.json"
  # "블록 이름(이벤트·매처) → 그 블록 안에 있어야 할 훅 명령" 을 awk로 단순 확인
  has() { # 이벤트, 매처(없으면 -), 찾을 글자
    # pat은 환경변수로 넘긴다(awk -v는 \" 를 " 로 바꿔 버려 JSON 글자와 안 맞음)
    PAT="$3" awk -v ev="\"$1\"" -v m="$2" '
      BEGIN { pat=ENVIRON["PAT"] }
      index($0, ev) { inev=1 }
      inev && /"(PreToolUse|PostToolUse|Stop|SessionStart|UserPromptSubmit)"/ && !index($0, ev) { inev=0 }
      inev && /"matcher"/ { cur=$0 }
      inev && index($0, pat) && (m=="-" || index(cur, "\"" m "\"")) { found=1 }
      END { exit found ? 0 : 1 }' "$S" && echo 등록됨 || echo 없음
  }
  row "등록: PreToolUse Bash|PowerShell → protect-tests" 등록됨 "$(has PreToolUse 'Bash|PowerShell' protect-tests.sh)"
  row "등록: PreToolUse Bash|PowerShell → check-approved commit" 등록됨 "$(has PreToolUse 'Bash|PowerShell' 'check-approved.sh\" commit')"
  row "등록: PreToolUse Bash|PowerShell → flag-redteam commit" 등록됨 "$(has PreToolUse 'Bash|PowerShell' 'flag-redteam.sh\" commit')"
  row "등록: PreToolUse Edit|Write|MultiEdit → protect-tests" 등록됨 "$(has PreToolUse 'Edit|Write|MultiEdit' protect-tests.sh)"
  row "등록: PreToolUse Edit|Write|MultiEdit|NotebookEdit → agent-memory-only" 등록됨 "$(has PreToolUse 'Edit|Write|MultiEdit|NotebookEdit' agent-memory-only.sh)"
  row "등록: Stop → check-approved stop" 등록됨 "$(has Stop - 'check-approved.sh\" stop')"
  row "등록: SessionStart startup → session-start" 등록됨 "$(has SessionStart startup session-start.sh)"
  row "등록: SessionStart resume|compact|clear → session-start" 등록됨 "$(has SessionStart 'resume|compact|clear' session-start.sh)"
  row "등록: UserPromptSubmit → graph-prompt" 등록됨 "$(has UserPromptSubmit - graph-prompt.sh)"
  row "등록: Stop → graph-stop" 등록됨 "$(has Stop - graph-stop.sh)"
  row "등록: Stop → check-tests stop (그대로)" 등록됨 "$(has Stop - 'check-tests.sh\" stop')"
  row "등록: PreToolUse Edit|Write|MultiEdit → guard-state" 등록됨 "$(has PreToolUse 'Edit|Write|MultiEdit' guard-state.sh)"
  for a in qa-reviewer red-team; do
    f="$src/.claude/agents/$a.md"
    r="없음"; grep -q '^memory: project' "$f" && grep -q 'agent-memory-only.sh" '"$a" "$f" && r="등록됨"
    row "등록: $a 에이전트 memory + 메모리 훅" 등록됨 "$r"
  done
  row "등록: PreToolUse Edit|Write|MultiEdit|NotebookEdit → team-files" 등록됨 "$(has PreToolUse 'Edit|Write|MultiEdit|NotebookEdit' team-files.sh)"
  for a in backend-dev frontend-dev; do
    f="$src/.claude/agents/$a.md"
    r="없음"; grep -q 'team-files.sh" '"$a" "$f" && grep -q '^model: sonnet' "$f" && r="등록됨"
    row "등록: $a 에이전트 sonnet + 파일 경계 훅" 등록됨 "$r"
  done
fi

echo "| 경우 | 기대 | 실제 | |"
echo "|---|---|---|---|$rows"
echo
if [ $fails -eq 0 ]; then echo "전부 기대대로입니다."; else echo "기대와 다른 경우: $fails개"; exit 1; fi

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

# ---- 5. 에이전트 메모리 (agent-memory-only.sh) ----
row "red-team이 자기 메모리 폴더에 Write" 통과 "$(run "$(agent_write_json red-team "$tmp/.claude/agent-memory/red-team/MEMORY.md")" agent-memory-only.sh)"
row "red-team이 앱 코드에 Write" 막힘 "$(run "$(agent_write_json red-team "$tmp/apps/demo/src/app.js")" agent-memory-only.sh)"
row "qa-reviewer가 red-team 메모리에 Write" 막힘 "$(run "$(agent_write_json qa-reviewer "$tmp/.claude/agent-memory/red-team/MEMORY.md")" agent-memory-only.sh)"
row "red-team이 ../ 로 빠져나가기" 막힘 "$(run "$(agent_write_json red-team "$tmp/.claude/agent-memory/red-team/../../hooks/x.sh")" agent-memory-only.sh)"
row "red-team이 Windows 경로로 메모리 Write" 통과 "$(run "$(agent_write_json red-team 'C:\work\.claude\agent-memory\red-team\MEMORY.md')" agent-memory-only.sh)"
row "frontmatter 방식(인자 qa-reviewer, agent_type 없음) 앱 코드" 막힘 "$(run "$(write_json "$tmp/apps/demo/src/app.js" "x")" agent-memory-only.sh qa-reviewer)"
row "메인 대화(agent_type 없음)가 앱 코드 Write" 통과 "$(run "$(write_json "$tmp/apps/demo/src/app.js" "x")" agent-memory-only.sh)"
row "다른 에이전트(test-runner)가 Write" 통과 "$(run "$(agent_write_json test-runner "$tmp/apps/demo/src/app.js")" agent-memory-only.sh)"

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

# ---- settings.json 등록 확인 (--settings) ----
if [ "$1" = "--settings" ]; then
  S="$src/.claude/settings.json"
  # "블록 이름(이벤트·매처) → 그 블록 안에 있어야 할 훅 명령" 을 awk로 단순 확인
  has() { # 이벤트, 매처(없으면 -), 찾을 글자
    # pat은 환경변수로 넘긴다(awk -v는 \" 를 " 로 바꿔 버려 JSON 글자와 안 맞음)
    PAT="$3" awk -v ev="\"$1\"" -v m="$2" '
      BEGIN { pat=ENVIRON["PAT"] }
      index($0, ev) { inev=1 }
      inev && /"(PreToolUse|PostToolUse|Stop|SessionStart)"/ && !index($0, ev) { inev=0 }
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
  for a in qa-reviewer red-team; do
    f="$src/.claude/agents/$a.md"
    r="없음"; grep -q '^memory: project' "$f" && grep -q 'agent-memory-only.sh" '"$a" "$f" && r="등록됨"
    row "등록: $a 에이전트 memory + 메모리 훅" 등록됨 "$r"
  done
fi

echo "| 경우 | 기대 | 실제 | |"
echo "|---|---|---|---|$rows"
echo
if [ $fails -eq 0 ]; then echo "전부 기대대로입니다."; else echo "기대와 다른 경우: $fails개"; exit 1; fi

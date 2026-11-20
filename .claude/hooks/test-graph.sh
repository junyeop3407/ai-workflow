#!/usr/bin/env bash
# 그래프 시험: 임시 폴더에 가짜 저장소·가짜 앱을 만들고 graph.sh·auto-lock.sh·graph-stop.sh·api-check.sh·backend.sh 를
# 실제로 돌려 "기대 / 실제" 표와 가짜 앱 이야기 표를 보여 준다. 실제 저장소·실제 앱 코드는 건드리지 않는다.
# (승인 스크립트를 불러야 해서 protect-tests.sh 가 허용하는 .claude/hooks/ 에 둔다)
# 사용: bash .claude/hooks/test-graph.sh   — 기대와 다른 줄이 하나라도 있으면 exit 1
# 테스트·리뷰·레드팀 결과는 모두 가짜(가정)다. node 가 없으면 backend.sh 시험은 "확인 못 함".

src="$(git rev-parse --show-toplevel)" || exit 1
H="$src/.claude/hooks"
GS="$src/.claude/skills/build-app/graph.sh"
G() { bash "$GS" "$@" </dev/null; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q . && git config user.email t@example.com && git config user.name tester && git config core.autocrlf false
mkdir -p docs && echo x > docs/x && git add -A && git commit -qm init

fails=0; rows=""
row() { local mark="✅"; if [ "$2" != "기록" ] && [ "$2" != "$3" ]; then mark="❌"; fails=$((fails+1)); fi
  rows="$rows
| $(printf '%s' "$1" | sed 's/|/\\|/g') | $2 | $(printf '%s' "$3" | sed 's/|/\\|/g') | $mark |"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
stj() { printf '{"session_id":"t","hook_event_name":"Stop","stop_hook_active":%s}' "$1"; }
gstop() { stj "${1:-false}" | bash "$H/graph-stop.sh" 2>"$tmp/.stop"; echo $?; }
st_of() { G get "apps/$1" status "$2" 2>/dev/null; }
cur_of() { G current "apps/$1" 2>/dev/null | head -n1; }
S() { printf 'apps/%s/state.json' "$1"; }

# 시험용 가짜 state: 새로 만든 뒤 모든 노드를 통과로 두고, 현재 노드·상태만 바꾼다
mkstate() { # 앱 현재노드 상태
  rm -rf "apps/$1"; mkdir -p "apps/$1/docs" "apps/$1/tests"
  printf '# %s\n현재 단계: 4\n테스트 실행: `bash tests/run.sh`\n백엔드 테스트: `bash tests/backend.sh`\n' "$1" > "apps/$1/HANDOFF.md"
  printf 'exit 0\n' > "apps/$1/tests/run.sh"; printf 'exit 0\n' > "apps/$1/tests/backend.sh"
  G init "apps/$1" >/dev/null 2>&1
  sed -i -E '/^    "/ s/"status": "[^"]*"/"status": "통과"/' "$(S "$1")"
  sed -i -E 's/^(    "done": \{"status": )"통과"/\1"대기"/' "$(S "$1")"
  sed -i -E "s/\"current\": \[[^]]*\]/\"current\": [\"$2\"]/; s/^(    \"$2\": \{\"status\": )\"[^\"]*\"/\1\"$3\"/" "$(S "$1")"
}
setst() { sed -i -E "s/^(    \"$2\": \{\"status\": )\"[^\"]*\"/\1\"$3\"/" "$(S "$1")"; }

# =============== A. 가짜 앱 이야기: 사장은 ★에서 보기만 누르고 명령은 0번 ===============
A=apps/shop
mkdir -p $A/docs $A/tests .claude/hooks
printf '# shop\n현재 단계: 1\n테스트 실행: `bash tests/run.sh`\n백엔드 테스트: `bash tests/backend.sh`\n' > $A/HANDOFF.md
# 가짜 Playwright: .pw 에 적힌 글자가 0 이면 통과, 아니면 그 이유로 실패
printf 'v=$(cat .pw 2>/dev/null || echo 0); [ "$v" = 0 ] && { echo "3 passed"; exit 0; }; echo "FAILED test_a 담기 — $v"; exit 1\n' > $A/tests/run.sh
echo "story" > "$(git rev-parse --git-dir)/graph-turn"   # 앱 작업 턴 (graph-prompt.sh 가 남기는 표시)
star=0; boss_cmd=0; q_after=0; phase=pre; story=""; step=0
snap() { # 단계 설명, 사장 입력
  step=$((step+1))
  local c sc ap rb rf
  c="$(G current $A --status | paste -sd' ' -)"
  sc="$(sed -n 's/.*"score": {"rounds": [0-9]*, "history": "\([^"]*\)".*/\1/p' "$(S shop)")"
  ap="$(grep -c '"answer"' "$(S shop)")"
  rb="$(sed -n 's/.*"bb": {"status": "[^"]*", "retries": \([0-9]*\), "boss_fixes": [0-9]*, "rounds": \([0-9]*\).*/되돌아옴 \1·회차 \2/p' "$(S shop)")"
  rf="$(sed -n 's/.*"bf": {"status": "[^"]*", "retries": \([0-9]*\), "boss_fixes": [0-9]*, "rounds": \([0-9]*\).*/되돌아옴 \1·회차 \2/p' "$(S shop)")"
  story="$story
| $step | $1 | $2 | ${c:-없음} | bb $rb / bf $rf | ${sc:--} | $ap |"
}
boss() { # ★ 클릭 한 번 = approve
  G approve $A "$1" "$2" >/dev/null; star=$((star+1)); [ "$phase" = impl ] && q_after=$((q_after+1)); G pass $A "$1" $3 >/dev/null; }

G init $A >/dev/null;                                   snap "init (새 앱)" "-"
G pass $A req >/dev/null;                               snap "기획 → ★기획 검토 대기" "-"
boss ok-req "OK";                                       snap "★기획 검토 OK → 설계안" "★ OK"
G pass $A opt >/dev/null; boss ok-opt "1번 안(추천)";    snap "설계안 → ★설계 선택 → 테스트 목록" "★ 1번"
G pass $A tl >/dev/null; boss ok-tl "OK";               snap "테스트 목록 → ★승인 → 테스트 코드" "★ OK"
printf "test('F1 장바구니 담기', () => {})\n" > $A/tests/test_a.spec.ts
G pass $A tc >/dev/null;                                snap "테스트 코드 → ⚙️ 자동 잠금 → 계획" "-"
row "첫 잠금 자동 (tc 통과 → auto-lock, 사장 명령 없음)" "잠김+ip" "$([ -f $A/tests/.approved ] && echo 잠김)+$(cur_of shop)"
row "잠긴 뒤 auto-lock 다시 부름 → 거부" 1 "$(rc bash "$H/auto-lock.sh" $A)"
G pass $A ip >/dev/null
G approve $A ok-ip "OK, 탐색·사용성은 건너뛰기" >/dev/null; star=$((star+1)); G budget $A 0 >/dev/null; G pass $A ok-ip >/dev/null
snap "계획 → ★계획 승인(+탐색 건너뛰기) → 디자인∥데이터" "★ OK·건너뛰기"
row "ui ∥ dd 동시 진행" "ui:진행 dd:진행" "$(G current $A --status | paste -sd' ' -)"
G pass $A ui >/dev/null; G pass $A dd >/dev/null
G approve $A ok-ui "OK" >/dev/null; star=$((star+1)); G pass $A ok-ui >/dev/null
row "합류: ok-ui만 통과 → bb 아직 시작 안 함" "ok-dd" "$(cur_of shop)"
G approve $A ok-dd "OK" >/dev/null; star=$((star+1)); G pass $A ok-dd >/dev/null
snap "디자인·데이터 → ★검토 2개 OK → 합류 → bb" "★ OK ×2"
row "합류 뒤 bb 시작" "bb" "$(cur_of shop)"
phase=impl
row "bb 진행 중 bf pass 시도 → 거부" 1 "$(rc G pass $A bf)"
printf 'v=$(cat .be 2>/dev/null || echo 0); [ "$v" = 0 ] && { echo "JUnit ok, api 1/1"; exit 0; }; echo "FAILED backend — $v"; exit 1\n' > $A/tests/backend.sh
echo "a" > $A/.pw    # Playwright(승인 테스트)는 아직 실패 — bb 통과에는 영향 없어야 함
echo "주문 저장 안 됨" > $A/.be
row "bb 자동 루프: 실패 → 막힘" 2 "$(gstop)"; snap "bb 자동 루프 1회 실패(Stop 훅)" "-"
echo "가격 계산 틀림" > $A/.be
gstop >/dev/null; snap "bb 자동 루프 2회 실패" "-"
row "bb 회차 +1씩 (2회)" 2 "$(sed -n 's/.*"bb": {"status": "[^"]*", "retries": [0-9]*, "boss_fixes": [0-9]*, "rounds": \([0-9]*\).*/\1/p' "$(S shop)")"
echo 0 > $A/.be
row "bb: Playwright 실패여도 백엔드 테스트 통과 → 자동 pass(막고 다음 노드)" "2+cb" "$(gstop)+$(cur_of shop)"
snap "bb 통과 → Codex 빠른 검수(cb)" "-"
G pass $A cb bf >/dev/null;                             snap "cb 마지막 단계 → bf" "-"
row "bf: Playwright 실패 → 통과 안 됨(자동 루프 계속)" "2+bf" "$(gstop)+$(cur_of shop)"
echo 0 > $A/.pw
gstop >/dev/null;                                       snap "bf 자동 루프 통과 → cf" "-"
G fail $A cf "Codex: 빈 장바구니에서 합계가 NaN" bf >/dev/null
snap "cf Codex 지적 1개 → 담당 bf로" "-"
row "Codex 지적 → 담당 노드(bf)로만" "bf" "$(cur_of shop)"
gstop >/dev/null;                                       snap "bf 고침 → 자동 pass → cf 다시" "-"
G pass $A cf ug >/dev/null;                             snap "cf 마지막 단계 → 화면 점검(ug)" "-"
G pass $A ug >/dev/null; G pass $A tr >/dev/null;      snap "ug → ⚙️ 테스트(tr) 통과 → 리뷰(qa)" "-"
G pass $A qa >/dev/null; G pass $A cx >/dev/null; G pass $A gm >/dev/null
snap "qa → Codex 교차 → Gemini 교차 (가정: 맞는 지적 해결)" "-"
printf 'LCP 1.8\nCLS 0.02\n콘솔에러 0\n실패요청 0\n부하에러율 0\np99 0.4\n' > $A/docs/perf.txt
G pass $A dv >/dev/null;                                snap "⚙️ DevTools·부하 통과 → 탐색(건너뜀) → 레드팀" "-"
row "ex: ok-ip에서 건너뛰기 → 다시 묻지 않고 건너뜀" "건너뜀" "$(st_of shop ex)"
printf '# 레드팀\n- [의심] [보통] 로그인 요청 횟수 — 해결: tests/test_a.spec.ts:1\n' > $A/docs/redteam.md
G pass $A rt >/dev/null; G pass $A sa >/dev/null;      snap "레드팀(⚙️ 표시 없음) → 보안 감사 → 점수(sc)" "-"
# 점수 1바퀴: 체크리스트 일부 ✗ (가정)
{ for i in $(seq 1 20); do case $i in 14|15|17|18) echo "| $i | ✗ | 근거: - |" ;; 13) echo "| $i | 해당 없음 | - |" ;; *) echo "| $i | ✓ | 근거: tests/test_a.spec.ts:1 |" ;; esac; done; } > $A/docs/checklist.md
printf '## 꼭 되어야 할 기능\n- F1 장바구니 담기\n' > $A/docs/requirements.md
printf -- '- F1 → 장바구니 담기 (tests/test_a.spec.ts)\n' > $A/docs/tests.md
G score $A >/dev/null 2>&1;                            snap "⚙️ 완성도 1바퀴 < 90% → 가장 많이 깎은 bf로 자동" "-"
row "점수 미달 → 담당 노드(bf)로 자동" "bf" "$(cur_of shop)"
sed -i 's/| ✗ | 근거: - |/| ✓ | 근거: tests\/test_a.spec.ts:1 |/' $A/docs/checklist.md
gstop >/dev/null; G pass $A tr >/dev/null;              snap "bf 고침 → 자동 pass → tr → sc 다시" "-"
G score $A >/dev/null 2>&1;                             snap "⚙️ 완성도 2바퀴 ≥ 90% → ★QA 보고 대기" "-"
phase=post
row "이야기 끝: ok-qa 사장 대기" "ok-qa:사장대기" "$(G current $A --status)"
row "사장 명령(! 한 줄) 횟수" 0 "$boss_cmd"
row "구현 시작 후 사장 질문 횟수" 0 "$q_after"
row "같은 노드 pass 두 번 → 그대로" "0+같음" "$(c1=$(cksum < "$(S shop)"); r=$(rc G pass $A sa); [ "$c1" = "$(cksum < "$(S shop)")" ] && echo "$r+같음" || echo "$r+바뀜")"
cp $A/tests/.approved "$tmp/.ap"; rm $A/tests/.approved
row "잠금 기록이 있는데 잠금 파일을 지움 → 멈춤(3)" 3 "$(rc G status $A)"
row "그 상태에서 auto-lock 다시 → 거부" 1 "$(rc bash "$H/auto-lock.sh" $A)"
cp "$tmp/.ap" $A/tests/.approved

# =============== B. 거부·한도·실패 엣지 ===============
mkstate t1 ok-req 사장대기
row "★ approve 없이 pass → 거부" 1 "$(rc G pass apps/t1 ok-req)"
row "없는 실패 엣지(ok-req → ui) → 거부" 1 "$(rc G fail apps/t1 ok-req "x" ui)"
out=""; for i in 1 2 3 4; do
  r=$(G fail apps/t1 ok-req "제목 바꿔" 2>&1); out="$out$?"; [ $i -eq 3 ] && echo "$r" | grep -q '방식을 바꾸자' && out="${out}안내"
  G pass apps/t1 req >/dev/null 2>&1; done
row "★ 수정 지시 4번 → 거부 없음 + 3번째 '방식을 바꾸자' 안내" "000안내0" "$out"
row "★에서 보낸 수정은 req 횟수에 안 셈" 0 "$(sed -n 's/.*"req": {"status": "[^"]*", "retries": \([0-9]*\).*/\1/p' "$(S t1)")"
mkstate t2 cb 진행; sed -i -E 's/("bb": \{"status": "[^"]*", "retries": )0/\15/' "$(S t2)"
row "AI 노드 횟수 초과(bb 되돌아옴 6번째) → 거부(4)" 4 "$(rc G fail apps/t2 cb "또 지적" bb)"
row "→ cb 상태 = 사장보고" 사장보고 "$(st_of t2 cb)"
mkstate t4 gm 진행
row "Gemini 지적 → 표에 없는 곳(req) 거부" 1 "$(rc G fail apps/t4 gm "x" req)"
G fail apps/t4 gm "Gemini: 주문 API 검증 누락" bb >/dev/null 2>&1
row "Gemini 지적 → bb만, 고친 뒤 갈 곳 = dv(1라운드)" "bb dv" "$(cur_of t4) $(sed -n 's/.*"resume": "\([^"]*\)".*/\1/p' "$(S t4)")"
mkstate t5 tc 진행
printf "test('x', () => {})\n" > apps/t5/tests/test_x.spec.ts
G pass apps/t5 tc >/dev/null 2>&1
row "ok-tl 승인 기록 없이 자동 잠금 → 거부(lock 사장보고, 잠금 파일 없음)" "사장보고 없음" "$(st_of t5 lock) $([ -f apps/t5/tests/.approved ] && echo 있음 || echo 없음)"
# 서버 없는 앱: dd·ok-dd·bb·cb 건너뜀 → 합류 뒤 바로 bf
mkstate t3 ok-ip 승인; sed -i 's/"ex_budget": ""/"ex_budget": "0"/' "$(S t3)"
for n in ui dd ok-ui ok-dd bb cb bf; do setst t3 $n 대기; done
G skip apps/t3 dd,ok-dd,bb,cb "서버 없음" >/dev/null; G pass apps/t3 ok-ip >/dev/null; G pass apps/t3 ui >/dev/null
G approve apps/t3 ok-ui OK >/dev/null; G pass apps/t3 ok-ui >/dev/null
row "서버 없는 앱: 합류 뒤 바로 bf" "bf" "$(cur_of t3)"
rm -rf apps/t1 apps/t2 apps/t3 apps/t4 apps/t5   # 아래 Stop 시험에 다른 앱이 끼지 않게
# 자동 루프 브레이크
mkstate t6 bf 진행; sed -i -E 's/("bf": \{"status": "[^"]*", "retries": [0-9]*, "boss_fixes": [0-9]*, "rounds": )0/\115/' "$(S t6)"
printf 'echo "FAILED x"; exit 1\n' > apps/t6/tests/run.sh
row "자동 루프 15회 초과 → 사장 보고(22)" 22 "$(rc G loop apps/t6)"
row "→ 다음 Stop은 정당한 멈춤(통과)" 0 "$(gstop true)"
mkstate t7 bb 진행; printf 'echo "FAILED 주문 저장"; exit 1\n' > apps/t7/tests/backend.sh
r7="$(rc G loop apps/t7),$(rc G loop apps/t7),$(rc G loop apps/t7)"
row "같은 이유 3회 연속 실패 → 3번째에 사장 보고" "20,20,22" "$r7"
mkstate t8 qa 진행
row "구현 노드가 아니면 loop 영향 없음(0)" 0 "$(rc G loop apps/t8)"
rm -rf apps/t1 apps/t2 apps/t4 apps/t5 apps/t6 apps/t7 apps/t8 apps/t3

# =============== C. 완성도 점수 ===============
mkscore() { mkstate "$1" sc 진행; setst "$1" dv 건너뜀
  printf "test('F1', () => {})\n" > "apps/$1/tests/test_a.spec.ts"; bash "$H/approve-tests.sh" "apps/$1" >/dev/null
  printf '# 레드팀\n' > "apps/$1/docs/redteam.md"; }
cl() { # 앱, ✗ 번호들, 해당 없음 번호들
  for i in $(seq 1 20); do
    if printf ' %s ' "$2" | grep -q " $i "; then echo "| $i | ✗ | 근거: - |"
    elif printf ' %s ' "$3" | grep -q " $i "; then echo "| $i | 해당 없음 | - |"
    else echo "| $i | ✓ | 근거: tests/test_a.spec.ts:1 |"; fi; done > "apps/$1/docs/checklist.md"; }
mkscore s1; cl s1 "" ""; touch apps/s1/.redteam-needed
row "필수 관문 실패(.redteam-needed) → 점수 상관없이 rt로" "rt" "$(G score apps/s1 >/dev/null 2>&1; cur_of s1)"
mkscore s2; cl s2 "19" ""
printf '## Claude 판단\n' > apps/s2/docs/review.md
for i in 1 2 3 4 5 6; do echo "- [맞음] 지적 $i — 해결: tests/test_a.spec.ts:1 — 담당: bb" >> apps/s2/docs/review.md; done
echo "- [맞음] 지적 7 — 해결: 아직 — 담당: bb" >> apps/s2/docs/review.md; echo "- [맞음] 지적 8 — 해결: 아직 — 담당: bb" >> apps/s2/docs/review.md
G score apps/s2 >/dev/null 2>&1
row "25/28 = 89% → 가장 많이 깎은 담당(bb)으로" "89% bb" "$(sed -n 's/.*"history": "\([0-9]*\)".*/\1/p' "$(S s2)")% $(cur_of s2)"
mkscore s3; cl s3 "19 20" ""
G score apps/s3 >/dev/null 2>&1
row "18/20 = 90% → ok-qa" "ok-qa" "$(cur_of s3)"
mkscore s4; cl s4 "16 17 18 19 20" ""; sed -i 's/"rounds": 0, "history": ""/"rounds": 2, "history": "75,75"/' "$(S s4)"
row "2바퀴 연속 정체 → 사장 보고(4)" "4 사장보고" "$(rc G score apps/s4) $(st_of s4 sc)"
mkscore s5; cl s5 "" ""; sed -i 's#| 3 | ✓ | 근거: tests/test_a.spec.ts:1 |#| 3 | ✓ | 근거: src/없는파일.ts:9 |#' apps/s5/docs/checklist.md
G score apps/s5 >/dev/null 2>&1
row "근거 없는 AI 항목(✓인데 파일 없음) → 미통과로 셈" "근거 없음" "$(grep -o '체크리스트 3 (근거 없음)' apps/s5/docs/score.md | sed 's/.*(\(.*\))/\1/')"
rm -rf apps/s1 apps/s2 apps/s3 apps/s4 apps/s5

# =============== D. ex 사용량, pub 비밀값, 깨진 state, migrate, lint ===============
mkstate e1 ex 진행; sed -i 's/"ex_budget": ""/"ex_budget": "1000"/' "$(S e1)"
G usage apps/e1 1500 >/dev/null
row "ex 사용량 1.5배 → 계속" 진행 "$(st_of e1 ex)"
G usage apps/e1 2500 >/dev/null
row "ex 사용량 2배 초과 → 멈춤 ④(사장대기)" 사장대기 "$(st_of e1 ex)"
mkstate p1 pub 사장대기; G approve apps/p1 pub "올려" >/dev/null
key="AKIA$(printf 'Q%.0s' $(seq 16))"; printf 'const k = "%s";\n' "$key" > apps/p1/app.js
row "pub: 가짜 키가 있으면 pass 거부" 1 "$(rc G pass apps/p1 pub dep)"
G pass apps/p1 pub dep 2>&1 | grep -q "$key" && leak=보임 || leak=안보임
row "→ 거부 메시지에 키 값이 보이지 않음" 안보임 "$leak"
rm apps/p1/app.js
row "pub: 비밀값 없으면 통과 → dep" "0 dep" "$(rc G pass apps/p1 pub dep) $(cur_of p1)"
mkstate b1 req 진행
: > "$(S b1)"; row "깨진 state.json: 빈 파일 → 멈춤(3)" 3 "$(rc G status apps/b1)"
printf '{\n  "version": 1,\n  oops\n' > "$(S b1)"; row "깨진 state.json: 형식 오류 → 멈춤(3)" 3 "$(rc G status apps/b1)"
mkstate b2 req 진행; sed -i 's/^    "req": /    "nope": /' "$(S b2)"
row "깨진 state.json: 없는 노드 → 멈춤(3)" 3 "$(rc G status apps/b2)"
mkstate b3 req 진행; sed -i 's/"status": "진행"/"status": "대충"/' "$(S b3)"
row "깨진 state.json: 모르는 상태 → 멈춤(3)" 3 "$(rc G status apps/b3)"
mkdir -p apps/m1; printf '# m1\n현재 단계: 4 (구현)\n' > apps/m1/HANDOFF.md
G migrate apps/m1 >/dev/null
row "migrate: 3단계까지 통과, 4단계 노드 확인 필요" "통과 통과 확인필요 대기" "$(st_of m1 ok-req) $(st_of m1 lock) $(st_of m1 bb) $(st_of m1 tr)"
row "migrate: ★ 승인 기록 '이전 방식'(ok-req·ok-opt·ok-tl)" 3 "$(grep -c '"answer": "이전 방식"' "$(S m1)")"
for n in ip ok-ip ui dd ok-ui ok-dd bb cb; do G confirm apps/m1 $n 통과 >/dev/null; done
G confirm apps/m1 bf 대기 >/dev/null; G confirm apps/m1 cf 대기 >/dev/null
row "migrate: 확인 필요를 다 정하면 첫 대기 노드부터" "bf" "$(cur_of m1)"
row "lint: graph.md 점검 통과" 0 "$(rc G lint)"
sed 's#| docs/data.md, docs/api.md |#| docs/data.md, docs/DESIGN.md |#' "$src/.claude/skills/build-app/graph.md" > "$tmp/bad.md"
row "lint: ui ∥ dd 가 같은 파일을 쓰게 바꾼 graph.md → 거부" 1 "$(GRAPH_MD="$tmp/bad.md" rc bash "$GS" lint)"
rm -rf apps/e1 apps/p1 apps/b1 apps/b2 apps/b3 apps/m1

# =============== E. api-check.sh · backend.sh (가짜 서버 = node) ===============
if command -v node >/dev/null 2>&1; then
  mkdir -p be/docs
  cat > be/srv.js <<'JS'
const http=require('http');http.createServer((q,r)=>{let b='';q.on('data',d=>b+=d);q.on('end',()=>{r.writeHead(q.method==='POST'?201:200,{'Content-Type':'application/json'});r.end(JSON.stringify({id:7,name:'우유',price:1000}));});}).listen(+process.env.P);
JS
  printf '### 요청: POST /api/items {"name": "우유", "price": 1000}\n### 응답: 201 {"id": "<아무거나>", "name": "우유", "price": 1000}\n' > be/docs/api.md
  printf '### 요청: POST /api/items {"name": "우유", "price": 1000}\n### 응답: 201 {"id": "<아무거나>", "name": "우유", "price": 900}\n' > be/docs/api-bad.md
  P=18431; export P
  port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
  BE() { (cd be && PORT=$P UNIT_TEST=true BUILD=true SERVER_CMD="node srv.js" SERVER_WAIT="${W:-10}" API_MD="${M:-docs/api.md}" \
        API_CHECK="$src/.claude/skills/build-app/api-check.sh" bash "$src/.claude/skills/build-app/templates/backend.sh" >"$tmp/.be.out" 2>&1); }
  BE; r=$?; row "backend.sh 정상 → 통과, 끝난 뒤 포트 닫힘" "0 닫힘" "$r $(port_open $P && echo 열림 || echo 닫힘)"
  M=docs/api-bad.md BE; r=$?; row "중간 실패(api 예시 값 다름) → 실패, 서버 안 남음" "1 닫힘" "$r $(port_open $P && echo 열림 || echo 닫힘)"
  row "api-check: 다른 값을 짚어 줌" 있음 "$(grep -q 'price' "$tmp/.be.out" && echo 있음 || echo 없음)"
  (cd be && PORT=$P UNIT_TEST=true BUILD=true SERVER_CMD="node -e 'setTimeout(()=>{},60000)'" SERVER_WAIT=30 \
     bash "$src/.claude/skills/build-app/templates/backend.sh" >"$tmp/.be.int" 2>&1) & bp=$!
  sleep 3; kill -INT $bp 2>/dev/null; wait $bp; r=$?
  row "기다리는 중 Ctrl+C(INT) → 멈춤, 서버 안 남음" "멈춤 없음" "$([ $r -ne 0 ] && echo 멈춤 || echo 안멈춤) $(grep -q '서버가 남았을' "$tmp/.be.int" && echo 남음 || echo 없음)"
  (cd be && P=$P exec node srv.js) & held=$!; sleep 2
  BE; r=$?
  row "포트 사용 중 → 바로 멈춤 + 안내" "1 안내" "$r $(grep -q "포트 $P 사용 중" "$tmp/.be.out" && echo 안내)"
  row "→ 미리 띄운 서버는 살아 있음" 살아있음 "$(port_open $P && echo 살아있음 || echo 꺼짐)"
  kill $held 2>/dev/null; [ -r "/proc/$held/winpid" ] && taskkill //F //PID "$(cat /proc/$held/winpid)" >/dev/null 2>&1; sleep 2
  (cd be && PORT=$P UNIT_TEST=true BUILD=true SERVER_CMD="node -e 'console.log(\"부팅 실패 흉내\"); setTimeout(()=>{},60000)'" SERVER_WAIT=3 \
     bash "$src/.claude/skills/build-app/templates/backend.sh" >"$tmp/.be.out" 2>&1); r=$?
  row "서버가 안 뜸(대기 3초) → 시간 초과 + 로그 끝 + 실패" "1 로그" "$r $(grep -q '부팅 실패 흉내' "$tmp/.be.out" && grep -q '3초 안에' "$tmp/.be.out" && echo 로그)"
else
  row "backend.sh·api-check 시험" 기록 "확인 못 함(node 없음)"
fi

echo "## 가짜 앱 이야기 (사장은 ★에서 보기만 누름 — 테스트·검수 결과는 가정)"
echo "| # | 무슨 일 | 사장 입력 | 현재 노드:상태 | 구현 회차 | 점수 기록 | 승인 수 |"
echo "|---|---|---|---|---|---|---|$story"
echo
echo "사장 명령: ${boss_cmd}번 / ★ 답: ${star}번 / 구현 시작 후 사장 질문: ${q_after}번"
echo
echo "## 시험"
echo "| 경우 | 기대 | 실제 | |"
echo "|---|---|---|---|$rows"
echo
if [ $fails -eq 0 ]; then echo "전부 기대대로입니다."; else echo "기대와 다른 경우: $fails개"; exit 1; fi

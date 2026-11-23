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

mk() { local f; for f in "$@"; do mkdir -p "$(dirname "$A/$f")"; echo "# 가짜 $f" > "$A/$f"; done; }   # AI 노드가 내는 파일(가정)
G init $A >/dev/null;                                   snap "init (새 앱)" "-"
mkreq() { # 앱 폴더 — 기획서 검사(req)를 통과하는 기획서
  printf '## 출시 안내문
- 이제 버튼 하나로 장바구니에 담을 수 있습니다.
## 예상 질문
- 저장되나요? → 네
## 성공 기준
- 장바구니 담기 3초 안
## 빈칸 점검표
- 사용자: 정함
- 예산: 나중(첫 버전 뒤)
## 꼭 되어야 할 기능
- F1 [1차·꼭] 장바구니 담기
  - F1-1 담기를 누르면 앱은 장바구니 수를 1 올린다 — 예: 사과 1개 → 장바구니 1
- F2 [나중·놀람] 추천 상품
' > "$1/docs/requirements.md"; }
mkreq $A; mk docs/review_req.md
G pass $A req >/dev/null;                               snap "기획 → ★기획 검토 대기" "-"
boss ok-req "OK";                                       snap "★기획 검토 OK → 법무 검토" "★ OK"
printf '# 법무 검토 — shop\n이 문서는 AI가 공개 자료를 읽고 정리한 것이며 법률 자문이 아님.\n## 판정\n- [GREEN] 회원 이메일 — 쓰는 방식: 로그인 — 조건: 개인정보처리방침 고지 — 근거: 개인정보 보호법 안내 (2026-11-23)\n' > $A/docs/legal.md
G pass $A lg >/dev/null; boss ok-lg "OK";              snap "법무 판정(GREEN) → ★법무 검토 OK → 설계안" "★ OK"
mk docs/spec.md docs/design.md docs/premortem.md
G pass $A opt >/dev/null; boss ok-opt "1번 안(추천)";    snap "설계안 → ★설계 선택 → 테스트 목록" "★ 1번"
printf -- '- F1-1 → 장바구니 담기 (tests/test_a.spec.ts)
' > $A/docs/tests.md
G pass $A tl >/dev/null; boss ok-tl "OK";               snap "테스트 목록 → ★승인 → 테스트 코드" "★ OK"
printf "test('F1 장바구니 담기', () => {})\n" > $A/tests/test_a.spec.ts
G pass $A tc >/dev/null;                                snap "테스트 코드 → ⚙️ 자동 잠금 → 계획" "-"
row "첫 잠금 자동 (tc 통과 → auto-lock, 사장 명령 없음)" "잠김+ip" "$([ -f $A/tests/.approved ] && echo 잠김)+$(cur_of shop)"
row "잠긴 뒤 auto-lock 다시 부름 → 거부" 1 "$(rc bash "$H/auto-lock.sh" $A)"
mk docs/plan.md; G pass $A ip >/dev/null
G approve $A ok-ip "OK, 탐색·사용성은 건너뛰기" >/dev/null; star=$((star+1)); G budget $A 0 >/dev/null; G pass $A ok-ip >/dev/null
snap "계획 → ★계획 승인(+탐색 건너뛰기) → 디자인∥데이터" "★ OK·건너뛰기"
row "ui ∥ dd 동시 진행" "ui:진행 dd:진행" "$(G current $A --status | paste -sd' ' -)"
mk docs/DESIGN.md docs/mockups/home.png docs/data.md docs/api.md
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
echo "주문 저장 안 됨" > $A/.be; mk docs/progress.md
row "bb 자동 루프: 실패 → 막힘" 2 "$(gstop)"; snap "bb 자동 루프 1회 실패(Stop 훅)" "-"
echo "가격 계산 틀림" > $A/.be
gstop >/dev/null; snap "bb 자동 루프 2회 실패" "-"
row "bb 회차 +1씩 (2회)" 2 "$(sed -n 's/.*"bb": {"status": "[^"]*", "retries": [0-9]*, "boss_fixes": [0-9]*, "rounds": \([0-9]*\).*/\1/p' "$(S shop)")"
echo 0 > $A/.be
row "bb: Playwright 실패여도 백엔드 테스트 통과 → 자동 pass(막고 다음 노드)" "2+cb" "$(gstop)+$(cur_of shop)"
snap "bb 통과 → Codex 빠른 검수(cb)" "-"
mk docs/review_codex.md
G pass $A cb bf >/dev/null;                             snap "cb 마지막 단계 → bf" "-"
row "bf: Playwright 실패 → 통과 안 됨(자동 루프 계속)" "2+bf" "$(gstop)+$(cur_of shop)"
echo 0 > $A/.pw
gstop >/dev/null;                                       snap "bf 자동 루프 통과 → cf" "-"
G fail $A cf "Codex: 빈 장바구니에서 합계가 NaN" bf >/dev/null
snap "cf Codex 지적 1개 → 담당 bf로" "-"
row "Codex 지적 → 담당 노드(bf)로만" "bf" "$(cur_of shop)"
gstop >/dev/null;                                       snap "bf 고침 → 자동 pass → cf 다시" "-"
G pass $A cf ug >/dev/null;                             snap "cf 마지막 단계 → 화면 점검(ug)" "-"
mk docs/ui-check.md
G pass $A ug >/dev/null; G pass $A tr >/dev/null;      snap "ug → ⚙️ 테스트(tr) 통과 → 리뷰(qa)" "-"
printf '## Claude 판단\n- [틀림] 없음 — 이유: 확인함\n' > $A/docs/review.md
row "qa: 잠금 뒤 생긴 준비 코드(tests/backend.sh)를 리뷰 안 함 → 거부" "1 qa" "$(rc G pass $A qa) $(cur_of shop)"
printf '\n## 준비 코드 변경\n- tests/backend.sh — 괜찮음: 백엔드 테스트 실행만\n' >> $A/docs/review.md
row "qa: 잠금 때 있던 run.sh도 첫 리뷰 대상(잠금 때 기록 안 함) → 거부" 1 "$(rc G pass $A qa)"
printf -- '- tests/run.sh — 괜찮음: 가짜 Playwright 실행\n' >> $A/docs/review.md
mk docs/review_result.md
G pass $A qa >/dev/null; G pass $A cx >/dev/null; G pass $A gm >/dev/null
snap "qa → Codex 교차 → Gemini 교차 (가정: 맞는 지적 해결)" "-"
printf 'LCP 1.8\nCLS 0.02\n콘솔에러 0\n실패요청 0\n부하에러율 0\np99 0.4\n' > $A/docs/perf.txt
G pass $A dv >/dev/null;                                snap "⚙️ DevTools·부하 통과 → 탐색(건너뜀) → 레드팀" "-"
row "ex: ok-ip에서 건너뛰기 → 다시 묻지 않고 건너뜀" "건너뜀" "$(st_of shop ex)"
printf '# 레드팀\n- [의심] [보통] 로그인 요청 횟수 — 해결: tests/test_a.spec.ts:1\n' > $A/docs/redteam.md
mk docs/security-audit.md
G pass $A rt >/dev/null; G pass $A sa >/dev/null;      snap "레드팀(⚙️ 표시 없음) → 보안 감사 → 점수(sc)" "-"
# 점수 1바퀴: 체크리스트 일부 ✗ (가정)
{ for i in $(seq 1 22); do case $i in 14|15|17|18) echo "| $i | ✗ | 근거: - |" ;; 13|21|22) echo "| $i | 해당 없음 | - |" ;; *) echo "| $i | ✓ | 근거: tests/test_a.spec.ts:1 |" ;; esac; done; } > $A/docs/checklist.md
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
mkstate t1 ok-req 사장대기; mkreq apps/t1; echo x > apps/t1/docs/review_req.md
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
echo '# 디자인' > apps/t3/docs/DESIGN.md; mkdir -p apps/t3/docs/mockups; echo png > apps/t3/docs/mockups/a.png
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
  printf 'echo "  1 passed (0.5s)"\n' > "apps/$1/tests/run.sh"
  printf '# 레드팀\n' > "apps/$1/docs/redteam.md"; }
cl() { # 앱, ✗ 번호들, 해당 없음 번호들
  for i in $(seq 1 22); do
    if printf ' %s ' "$2" | grep -q " $i "; then echo "| $i | ✗ | 근거: - |"
    elif printf ' %s 21 22 ' "$3" | grep -q " $i "; then echo "| $i | 해당 없음 | - |"   # 21·22(법무)는 점수 시험에서 해당 없음
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
row "migrate: ★ 승인 기록 '이전 방식'(ok-req·ok-lg·ok-opt·ok-tl)" 4 "$(grep -c '"answer": "이전 방식"' "$(S m1)")"
for n in ip ok-ip ui dd ok-ui ok-dd bb cb; do G confirm apps/m1 $n 통과 >/dev/null; done
G confirm apps/m1 bf 대기 >/dev/null; G confirm apps/m1 cf 대기 >/dev/null
row "migrate: 확인 필요를 다 정하면 첫 대기 노드부터" "bf" "$(cur_of m1)"
row "lint: graph.md 점검 통과" 0 "$(rc G lint)"
# ---- 잠금(lock.sh): state:<앱>·env:port ----
LK="$H/lock.sh"
mkstate z1 req 진행
sleep 30 >/dev/null 2>&1 & zh=$!; ztok="$(bash "$LK" acquire state:z1 --pid $zh)"
row "다른 작업이 state 잠금을 잡음 → 쓰는 명령은 기다리다 멈춤(4)" 4 "$(GRAPH_LOCK_WAIT=2 rc G stuck apps/z1 req 보고 시험)"
row "그동안 읽는 명령(current)은 그대로" req "$(cur_of z1)"
kill $zh 2>/dev/null; wait $zh 2>/dev/null
row "잡은 작업이 끝남 → 자동 회수하고 쓰는 명령 진행" 0 "$(rc G stuck apps/z1 req 보고 시험)"
G resume apps/z1 req >/dev/null 2>&1
n0=$(grep -c '"do": ' "$(S z1)")
G stuck apps/z1 req 보고 "동시1" >/dev/null 2>&1 & c1=$!; G stuck apps/z1 req 보고 "동시2" >/dev/null 2>&1 & c2=$!; wait $c1 $c2
row "쓰는 명령 둘을 동시에 → 기록 둘 다 남음(덮어쓰기 없음)" 2 "$(( $(grep -c '"do": ' "$(S z1)") - n0 ))"
mkstate z2 tr 진행; printf 'echo "  1 passed (0.1s)"\n' > apps/z2/tests/run.sh
sleep 30 >/dev/null 2>&1 & zh=$!; ztok="$(bash "$LK" acquire env:port:default --pid $zh)"
row "포트 잠금을 다른 테스트가 잡음 → 테스트 실행은 기다리다 실패 + 이유" "1 잠금" "$(TEST_LOCK_WAIT=2 bash "$H/check-tests.sh" app apps/z2 >"$tmp/z2.out" 2>&1; echo "$? $(grep -q '테스트 환경 잠금' "$tmp/z2.out" && echo 잠금)")"
kill $zh 2>/dev/null; wait $zh 2>/dev/null
row "포트 잠금이 풀림 → 테스트 실행 통과" 0 "$(bash "$H/check-tests.sh" app apps/z2 >/dev/null 2>&1; echo $?)"
printf '포트: 8091\n' >> apps/z2/HANDOFF.md
sleep 30 >/dev/null 2>&1 & zh=$!; ztok="$(bash "$LK" acquire env:port:default --pid $zh)"
row "HANDOFF에 '포트: 8091' → default 잠금과 상관없이 바로 실행" 0 "$(TEST_LOCK_WAIT=2 bash "$H/check-tests.sh" app apps/z2 >/dev/null 2>&1; echo $?)"
kill $zh 2>/dev/null; wait $zh 2>/dev/null

# ---- 법무 판정서 검사 (lg) ----
mklg() { mkstate "$1" lg 진행; mkreq "apps/$1"; printf '## 외부 자료·데이터\n- 향수 목록 — 출처: https://example.com — 쓰는 방식: 화면 표시\n' >> "apps/$1/docs/requirements.md"; }
lgok='이 문서는 AI가 정리한 것이며 법률 자문이 아님.\n## 판정\n'
mklg l1; row "lg: legal.md 없음 → 거부" "1 lg" "$(rc G pass apps/l1 lg) $(cur_of l1)"
printf "$lgok"'- [GREEN] 향수 목록 — 쓰는 방식: 화면 표시 — 조건: 출처 표시\n' > apps/l1/docs/legal.md
row "lg: 근거: 없는 판정 → 거부" "1 lg" "$(rc G pass apps/l1 lg) $(cur_of l1)"
printf "$lgok"'- [RED] 향수 목록 — 쓰는 방식: 화면 표시 — 근거: 약관 2조 (2026-11-23)\n' > apps/l1/docs/legal.md
row "lg: RED인데 조치: 없음 → 거부" "1 lg" "$(rc G pass apps/l1 lg) $(cur_of l1)"
printf "$lgok"'- [GREEN] 다른 자료 — 쓰는 방식: 참고 — 근거: x (2026-11-23)\n' > apps/l1/docs/legal.md
row "lg: 기획서 외부 자료(향수 목록) 판정 빠짐 → 거부" "1 lg" "$(rc G pass apps/l1 lg) $(cur_of l1)"
printf '## 판정\n- [GREEN] 향수 목록 — 쓰는 방식: 화면 표시 — 근거: x (2026-11-23)\n' > apps/l1/docs/legal.md
row "lg: '법률 자문이 아님' 문구 없음 → 거부" "1 lg" "$(rc G pass apps/l1 lg) $(cur_of l1)"
printf "$lgok"'- [RED] 향수 목록 — 쓰는 방식: 화면 표시 — 근거: 약관 2조 (2026-11-23) — 조치: 대체: 공식 API\n' > apps/l1/docs/legal.md
row "lg: RED + 조치 있음 → 통과(★법무 검토에서 사장이 고름)" "0 ok-lg" "$(rc G pass apps/l1 lg) $(cur_of l1)"
G approve apps/l1 ok-lg "대체 자료 찾기" >/dev/null
row "ok-lg → req(요구사항 변경): 경영팀 영향 분석 없음 → 거부" "1 ok-lg" "$(rc G fail apps/l1 ok-lg "대체 자료 찾기" req) $(cur_of l1)"
printf '# 운영 기록\n## 영향 분석: ok-lg → req (2026-11-23)\n- 영향: 기획서 외부 자료 바뀜\n- 다시 돌 노드: req → ok-req → lg → ok-lg\n' > apps/l1/docs/ops.md
row "영향 분석에 '- 추천:' 줄 없음 → 거부" 1 "$(rc G fail apps/l1 ok-lg "대체 자료 찾기" req)"
printf -- '- 추천: 지금 바꾸기 — 공식 API로 대체\n' >> apps/l1/docs/ops.md
row "ok-lg: 영향 분석 + 승인 기록 → 기획(req)으로 되돌림" "0 req" "$(rc G fail apps/l1 ok-lg "대체 자료 찾기" req) $(cur_of l1)"
mkstate m3 ok-qa 사장대기
printf '# 운영 기록\n## 영향 분석: ok-qa → tl (2026-11-23)\n- 영향: 테스트 목록 F3-1 추가\n- 다시 돌 노드: tl → ok-tl → tc → lock\n- 추천: 지금 바꾸기\n' > apps/m3/docs/ops.md
row "ok-qa → tl(요구사항 변경): 영향 분석은 있는데 사장 승인 없음 → 거부" 1 "$(rc G fail apps/m3 ok-qa "결제 내역 내보내기도 필요" tl)"
G approve apps/m3 ok-qa "테스트 목록에 추가해서 진행" >/dev/null
row "ok-qa → tl: 영향 분석 + 승인 → 통과" "0 tl" "$(rc G fail apps/m3 ok-qa "결제 내역 내보내기도 필요" tl) $(cur_of m3)"
mkstate m4 ok-qa 사장대기
row "ok-qa → bf(아직이에요)는 요구사항 변경이 아니라 분석 없이 통과" "0 bf" "$(rc G fail apps/m4 ok-qa "버튼이 아직 안 보여요" bf) $(cur_of m4)"
mkstate l2 lg 진행; setst l2 ok-lg 대기; setst l2 opt 대기; G skip apps/l2 lg "법무 해당 없음" >/dev/null
row "lg 건너뛰기 → ok-lg도 함께 건너뛰고 설계안(opt)으로" "건너뜀 건너뜀 opt" "$(st_of l2 lg) $(st_of l2 ok-lg) $(cur_of l2)"
sed 's#| docs/data.md, docs/api.md |#| docs/data.md, docs/DESIGN.md |#' "$src/.claude/skills/build-app/graph.md" > "$tmp/bad.md"
row "lint: ui ∥ dd 가 같은 파일을 쓰게 바꾼 graph.md → 거부" 1 "$(GRAPH_MD="$tmp/bad.md" rc bash "$GS" lint)"
rm -rf apps/e1 apps/p1 apps/b1 apps/b2 apps/b3 apps/m1

# =============== G. 앞단계 문서 검사 (기획서·대조·안 정한 것) ===============
mkstate q1 req 진행; mkreq apps/q1; echo x > apps/q1/docs/review_req.md
sed -i 's/- 예산: 나중(첫 버전 뒤)/- 예산: 묻기/' apps/q1/docs/requirements.md
row "req: 빈칸 점검표에 '묻기' 남음 → 거부" "1 req" "$(rc G pass apps/q1 req) $(cur_of q1)"
mkreq apps/q1; sed -i '/F1-1/d' apps/q1/docs/requirements.md
row "req: 기능에 수용 기준 없음 → 거부" "1 req" "$(rc G pass apps/q1 req) $(cur_of q1)"
mkreq apps/q1; sed -i '/성공 기준/,/^## 빈칸/{/^- /d}' apps/q1/docs/requirements.md
row "req: 성공 기준 없음 → 거부" "1 req" "$(rc G pass apps/q1 req) $(cur_of q1)"
mkreq apps/q1; rm apps/q1/docs/review_req.md
row "req: Gemini 비판(review_req.md) 없음 → 거부" "1 req" "$(rc G pass apps/q1 req) $(cur_of q1)"
printf '## Gemini 지적\n- [높음] 성공 기준 — 모호함\n## Claude 판단\n' > apps/q1/docs/review_req.md
row "req: Gemini 지적은 있는데 Claude 판단이 빔 → 거부" "1 req" "$(rc G pass apps/q1 req) $(cur_of q1)"
printf '## Gemini 지적\n- [높음] 성공 기준 — 모호함\n## Claude 판단\n- [맞음] 성공 기준 — 해결: docs/requirements.md:2\n' > apps/q1/docs/review_req.md
row "req: 정상 → 통과(★기획 검토로)" "0 ok-req" "$(rc G pass apps/q1 req) $(cur_of q1)"
mkstate q5 req 진행; echo x > apps/q5/docs/review_req.md
mkreq apps/q5; sed -i 's/- F1 \[1차·꼭\] /- F1 /' apps/q5/docs/requirements.md
row "req: 기능에 [1차|나중·꼭|많을수록|놀람] 표시 없음 → 거부" "1 req" "$(rc G pass apps/q5 req) $(cur_of q5)"
mkreq apps/q5; sed -i 's/ — 예: 사과 1개 → 장바구니 1//' apps/q5/docs/requirements.md
row "req: 수용 기준에 예시(— 예:) 없음 → 거부" "1 req" "$(rc G pass apps/q5 req) $(cur_of q5)"
mkreq apps/q5; sed -i '/^## 출시 안내문/,/^## 예상/{/^- /d}' apps/q5/docs/requirements.md
row "req: 출시 안내문 없음 → 거부" "1 req" "$(rc G pass apps/q5 req) $(cur_of q5)"
mkreq apps/q5; sed -i 's/\[1차·꼭\]/[나중·꼭]/' apps/q5/docs/requirements.md
row "req: 1차 기능이 하나도 없음 → 거부" "1 req" "$(rc G pass apps/q5 req) $(cur_of q5)"
mkreq apps/q5
row "req: 나중 기능(F2)은 수용 기준 없어도 → 통과" "0 ok-req" "$(rc G pass apps/q5 req) $(cur_of q5)"
rm -rf apps/q5
mkstate q2 tl 진행; mkreq apps/q2
printf -- '- F1-1 → 담기 (tests/a.spec.ts)\n- F2 → 추천 (tests/b.spec.ts)\n' > apps/q2/docs/tests.md
row "tl: 나중 기능 F2에 테스트를 만듦 → 거부" "1 tl" "$(rc G pass apps/q2 tl) $(cur_of q2)"
printf -- '- F1 → 담기 (tests/a.spec.ts)
' > apps/q2/docs/tests.md
row "tl: 수용 기준 F1-1에 테스트 없음 → 거부" "1 tl" "$(rc G pass apps/q2 tl) $(cur_of q2)"
printf -- '- F1-1 → 담기 (tests/a.spec.ts)
- F9-1 → 없는 기능 (tests/b.spec.ts)
' > apps/q2/docs/tests.md
row "tl: 기획서에 없는 번호 F9-1 → 거부" "1 tl" "$(rc G pass apps/q2 tl) $(cur_of q2)"
printf -- '- F1-1 → 담기 (tests/a.spec.ts)
' > apps/q2/docs/tests.md
row "tl: 정상 → 통과(★테스트 승인으로)" "0 ok-tl" "$(rc G pass apps/q2 tl) $(cur_of q2)"
mkstate q3 ip 진행; echo x > apps/q3/docs/plan.md
printf '## 아직 안 정한 것
- 결제 수단
- 알림 시간 — 나중: 첫 버전엔 없음
' > apps/q3/docs/spec.md
row "ip: '아직 안 정한 것'에 이유 없는 항목 → 거부" "1 ip" "$(rc G pass apps/q3 ip) $(cur_of q3)"
printf '## 아직 안 정한 것
- 알림 시간 — 나중: 첫 버전엔 없음
' > apps/q3/docs/spec.md
row "ip: 모두 '나중:' → 통과(★계획 승인으로)" "0 ok-ip" "$(rc G pass apps/q3 ip) $(cur_of q3)"
mkstate q4 opt 진행; echo x > apps/q4/docs/spec.md; echo x > apps/q4/docs/design.md
row "opt: 사전 부검(premortem.md) 없음 → 거부" "1 opt" "$(rc G pass apps/q4 opt) $(cur_of q4)"
rm -rf apps/q1 apps/q2 apps/q3 apps/q4

# =============== F. 검증에서 나온 4가지 (테스트 개수·준비 코드 리뷰·내는 것·건너뛰기 연쇄·표에 없는 다음) ===============
# F1. 테스트 개수: 실행 결과에서 통과 수 ≥ 승인된 테스트 수, 건너뜀 0, 0개 아님. 못 읽으면 통과 아님
mkcnt() { # 앱, run.sh 내용 — 승인된 테스트 2개(a, b)를 잠그고 tr 진행
  mkstate "$1" tr 진행
  printf "test('a', () => {})\ntest('b', async () => {})\n" > "apps/$1/tests/a.spec.ts"
  bash "$H/approve-tests.sh" "apps/$1" >/dev/null
  printf '%s\n' "$2" > "apps/$1/tests/run.sh"
}
mkcnt c1 'exit 0'
row "tr: run.sh를 exit 0으로 위조(출력 없음) → 거부" "1 tr" "$(rc G pass apps/c1 tr) $(cur_of c1)"
mkcnt c2 'printf "  1 skipped\n  1 passed (1.0s)\n"; exit 0'
row "tr: 테스트 하나 skip(1 passed, 1 skipped) → 거부" "1 tr" "$(rc G pass apps/c2 tr) $(cur_of c2)"
mkcnt c3 'echo "모두 좋음"; exit 0'
row "tr: 개수를 못 읽음 → 거부" "1 tr" "$(rc G pass apps/c3 tr) $(cur_of c3)"
mkcnt c4 'printf "  1 passed (1.0s)\n"; exit 0'
row "tr: 통과 1 < 승인된 테스트 2 → 거부" "1 tr" "$(rc G pass apps/c4 tr) $(cur_of c4)"
mkcnt c5 'printf "Running 2 tests using 1 worker\n  2 passed (1.2s)\n"; exit 0'
row "tr: 정상(2 passed = 승인 2) → 통과" "0 qa" "$(rc G pass apps/c5 tr) $(cur_of c5)"
G pass apps/c2 tr 2>&1 | grep -q '건너뜀' && m=있음 || m=없음
row "→ 거부 메시지에 건너뜀 개수가 보임" 있음 "$m"
mkcnt c6 'exit 0'; G fail apps/c6 tr "x" bf >/dev/null 2>&1; echo '| 회차 |' > apps/c6/docs/progress.md
row "bf 자동 루프: run.sh exit 0 → 통과 아님(20)" 20 "$(rc G loop apps/c6)"
mkscore c7; cl c7 "" ""; printf 'exit 0\n' > apps/c7/tests/run.sh
row "sc 필수 관문: run.sh exit 0(개수 없음) → bf로" "bf" "$(G score apps/c7 >/dev/null 2>&1; cur_of c7)"
rm -rf apps/c1 apps/c2 apps/c3 apps/c4 apps/c5 apps/c6 apps/c7
# 출력 형식별 개수 읽기 (graph.sh tcount: 표준 입력 → "통과 N 건너뜀 N 실패 N 형식 N")
tc_of() { printf '%b' "$1" | bash "$GS" tcount 2>/dev/null; }
row "개수: Playwright" "통과 3 건너뜀 1 실패 0 형식 1" "$(tc_of '  1 skipped\n  3 passed (2.1s)\n')"
row "개수: Vitest" "통과 2 건너뜀 1 실패 0 형식 1" "$(tc_of ' Test Files  1 passed (1)\n      Tests  2 passed | 1 skipped (3)\n')"
row "개수: pytest" "통과 4 건너뜀 1 실패 0 형식 1" "$(tc_of '....s\n===== 4 passed, 1 skipped in 0.12s =====\n')"
row "개수: pytest -q" "통과 2 건너뜀 0 실패 0 형식 1" "$(tc_of '..\n2 passed in 0.01s\n')"
row "개수: JUnit(Maven, 마지막 합계 줄)" "통과 5 건너뜀 1 실패 0 형식 1" "$(tc_of 'Tests run: 3, Failures: 0, Errors: 0, Skipped: 1, Time elapsed: 0.1 s - in a.ATest\nResults:\nTests run: 6, Failures: 0, Errors: 0, Skipped: 1\n')"
row "개수: JUnit(Gradle testLogging)" "통과 2 건너뜀 1 실패 0 형식 1" "$(tc_of 'ItemTest > create() PASSED\nItemTest > list() PASSED\nItemTest > old() SKIPPED\n')"
row "개수: Jest" "통과 2 건너뜀 1 실패 0 형식 1" "$(tc_of 'Tests:       1 skipped, 2 passed, 3 total\n')"
row "개수: node --test" "통과 3 건너뜀 1 실패 0 형식 1" "$(tc_of 'ℹ tests 4\nℹ pass 3\nℹ fail 0\nℹ skipped 1\nℹ todo 0\n')"
row "개수: 두 도구(Vitest + Playwright) 합침" "통과 5 건너뜀 0 실패 0 형식 2" "$(tc_of '      Tests  2 passed (2)\n  3 passed (1.0s)\n')"
row "개수: 못 읽음" "통과 0 건너뜀 0 실패 0 형식 0" "$(tc_of 'ok\n')"

# F2. 준비 코드(run.sh·conftest.py·fixtures·playwright.config)가 바뀌면 qa가 그 diff를 보게
mkstate q1 qa 진행; printf "test('a', () => {})\n" > apps/q1/tests/a.spec.ts; bash "$H/approve-tests.sh" apps/q1 >/dev/null
echo 'import pytest' > apps/q1/tests/conftest.py   # 잠금 뒤 생긴 준비 코드
printf '## Claude 판단\n- [틀림] 없음 — 이유: 확인함\n' > apps/q1/docs/review.md
row "qa: 준비 코드 기록 없음(첫 리뷰) + review.md에 준비 코드 절 없음 → 거부" "1 qa" "$(rc G pass apps/q1 qa) $(cur_of q1)"
G pass apps/q1 qa 2>&1 | grep -q 'tests/run.sh' && m=있음 || m=없음
row "→ 거부 메시지에 볼 파일(tests/run.sh)이 보임" 있음 "$m"
printf '\n## 준비 코드 변경\n- tests/run.sh — 괜찮음: 실행만\n' >> apps/q1/docs/review.md
row "→ 절은 있는데 tests/conftest.py 빠짐 → 거부" 1 "$(rc G pass apps/q1 qa)"
printf -- '- tests/conftest.py — 괜찮음: import만\n' >> apps/q1/docs/review.md
row "→ 바뀐 준비 코드를 모두 적음 → 통과(cx)" "0 cx" "$(rc G pass apps/q1 qa) $(cur_of q1)"
back_to_qa() { sed -i -E 's/"current": \[[^]]*\]/"current": ["qa"]/; s/^(    "qa": \{"status": )"[^"]*"/\1"진행"/' "$(S q1)"; }
back_to_qa; printf '## Claude 판단\n- [틀림] 없음 — 이유: 확인함\n' > apps/q1/docs/review.md
row "qa 다시: 지난 리뷰 뒤 준비 코드 안 바뀜 → 절 없어도 통과" "0 cx" "$(rc G pass apps/q1 qa) $(cur_of q1)"
back_to_qa; echo '# 기다리는 시간 늘림' >> apps/q1/tests/run.sh
row "qa 다시: run.sh 바뀜 → 절 없으면 거부" 1 "$(rc G pass apps/q1 qa)"
mkdir -p apps/q1/tests/fixtures; echo '{}' > apps/q1/tests/fixtures/a.json; echo 'export default {}' > apps/q1/playwright.config.ts
printf '\n## 준비 코드 변경\n- tests/run.sh — 괜찮음\n' >> apps/q1/docs/review.md
row "→ fixtures·playwright.config도 새로 생김 → 빠지면 거부" 1 "$(rc G pass apps/q1 qa)"
printf -- '- tests/fixtures/a.json — 괜찮음\n- playwright.config.ts — 괜찮음\n' >> apps/q1/docs/review.md
row "→ 모두 적으면 통과" 0 "$(rc G pass apps/q1 qa)"
rm -rf apps/q1
# 보안 리뷰 지적: 경로 정규식 끼워 넣기, 점 파일·러너 설정 빠짐
mkstate q2 qa 진행; printf "test('a', () => {})\n" > apps/q2/tests/a.spec.ts; bash "$H/approve-tests.sh" apps/q2 >/dev/null
echo 'exit 0' > 'apps/q2/tests/a+b.sh'
printf '## 준비 코드 변경\n- tests/run.sh — 괜찮음\n- tests/aab.sh — 괜찮음\n' > apps/q2/docs/review.md
row "qa: 파일 a+b.sh 대신 aab.sh를 적음(정규식처럼 맞춰짐) → 거부" 1 "$(rc G pass apps/q2 qa)"
printf -- '- tests/a+b.sh — 괜찮음\n' >> apps/q2/docs/review.md
echo 'export X=1' > apps/q2/tests/.setup.sh
row "qa: 점으로 시작하는 준비 코드(tests/.setup.sh) → 적어야 함" 1 "$(rc G pass apps/q2 qa)"
printf -- '- tests/.setup.sh — 괜찮음\n' >> apps/q2/docs/review.md
echo '{"scripts":{"test":"exit 0"}}' > apps/q2/package.json; echo 'test {}' > apps/q2/build.gradle
row "qa: 러너 설정(package.json·build.gradle) → 적어야 함" 1 "$(rc G pass apps/q2 qa)"
printf -- '- package.json — 괜찮음\n- `build.gradle` — 괜찮음\n' >> apps/q2/docs/review.md
row "→ 모두 적으면 통과(경로에 백틱 있어도 같은 경로로 셈)" 0 "$(rc G pass apps/q2 qa)"
rm -rf apps/q2

# F3. AI 노드 "내는 것" 파일이 있고 비어 있지 않아야 pass
mkstate o1 req 진행
row "req: requirements.md 없이 pass → 거부" "1 req" "$(rc G pass apps/o1 req) $(cur_of o1)"
: > apps/o1/docs/requirements.md
row "req: requirements.md가 빈 파일 → 거부" 1 "$(rc G pass apps/o1 req)"
mkreq apps/o1; echo x > apps/o1/docs/review_req.md
row "req: 기획서 검사에 맞는 requirements.md + review_req.md → 통과(ok-req)" "0 ok-req" "$(rc G pass apps/o1 req) $(cur_of o1)"
mkstate o2 ui 진행; echo '# 디자인' > apps/o2/docs/DESIGN.md; mkdir -p apps/o2/docs/mockups
row "ui: 시안 폴더(docs/mockups/)가 비어 있음 → 거부" 1 "$(rc G pass apps/o2 ui)"
echo png > apps/o2/docs/mockups/home.png
row "ui: 시안 파일 있음 → 통과" 0 "$(rc G pass apps/o2 ui)"
mkstate o3 dep 진행
row "dep: 파일이 아닌 칸(공개 주소)은 확인 안 함 → 통과" 0 "$(rc G pass apps/o3 dep)"
rm -rf apps/o1 apps/o2 apps/o3

# F4. 건너뛰기 연쇄: 같은 이유("서버 없음"/"화면 없음")를 가진 노드를 함께 건너뜀
mkk() { mkstate "$1" ok-ip 승인; sed -i 's/"ex_budget": ""/"ex_budget": "0"/' "$(S "$1")"
  for n in ui dd ok-ui ok-dd bb cb bf ug; do setst "$1" $n 대기; done; }
mkk k1; G skip apps/k1 bb "서버 없음" >/dev/null
row "bb만 건너뛰기(서버 없음) → dd·ok-dd·cb도 건너뜀" "건너뜀 건너뜀 건너뜀" "$(st_of k1 dd) $(st_of k1 ok-dd) $(st_of k1 cb)"
echo '# 디자인' > apps/k1/docs/DESIGN.md; mkdir -p apps/k1/docs/mockups; echo png > apps/k1/docs/mockups/a.png
G pass apps/k1 ok-ip >/dev/null; G pass apps/k1 ui >/dev/null; G approve apps/k1 ok-ui OK >/dev/null; G pass apps/k1 ok-ui >/dev/null
row "→ 합류 뒤 bf로" "bf" "$(cur_of k1)"
mkk k2; G skip apps/k2 ui "화면 없음" >/dev/null
row "ui만 건너뛰기(화면 없음) → ok-ui·ug도 건너뜀, 서버 쪽은 그대로" "건너뜀 건너뜀 대기" "$(st_of k2 ok-ui) $(st_of k2 ug) $(st_of k2 bb)"
rm -rf apps/k1 apps/k2

# F5. pass에 표에 없는 다음 노드를 주면 거부
mkstate n1 sa 진행; echo '# 보안 감사' > apps/n1/docs/security-audit.md; echo '# 법무 출시 전 점검' > apps/n1/docs/legal.md
row "sa 다음에 표에 없는 bf → 거부, 그대로 sa" "1 sa" "$(rc G pass apps/n1 sa bf) $(cur_of n1)"
row "sa 다음에 없는 노드 zzz → 거부" 1 "$(rc G pass apps/n1 sa zzz)"
row "sa 다음에 표에 있는 sc → 통과" "0 sc" "$(rc G pass apps/n1 sa sc) $(cur_of n1)"
mkstate n2 ok-req 사장대기; G approve apps/n2 ok-req OK >/dev/null
row "★ ok-req 다음에 표에 없는 bf → 거부" 1 "$(rc G pass apps/n2 ok-req bf)"
rm -rf apps/n1 apps/n2

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

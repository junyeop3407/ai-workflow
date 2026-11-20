#!/usr/bin/env bash
# graph.sh — build-app 그래프(graph.md)대로 앱 작업 순서를 지키고 상태(apps/<앱>/state.json)를 기록한다.
# 사용: bash .claude/skills/build-app/graph.sh <명령> apps/<앱> [인자…]   (명령 목록은 맨 아래 usage)
# - graph.md의 표만 읽는다. 표에 없는 노드·엣지는 거부한다. state.json은 이 스크립트만 쓴다.
# - 깨진 state.json(빈 파일·형식 오류·없는 노드·모르는 상태)은 고치지 않고 멈춘다(exit 3).
# - jq 없이, 연관 배열 없이 동작한다(Windows Git Bash, Mac bash 3.2).
# - 테스트 잠금 파일 이름은 이 파일에 쓰지 않는다(protect-tests.sh 규칙). 잠금 확인은 check-approved.sh lock,
#   첫 잠금은 auto-lock.sh, 다시 잠그는 안내 줄은 graph.md 에서 읽는다.
# 종료 코드: 0 성공 / 1 거부 / 3 state.json 깨짐 / 4 횟수 초과 → 사장 보고
#           loop: 0 구현 노드 아님 / 20 실패·계속 고침 / 21 통과·다음 노드 / 22 사장 보고

SDIR="$(cd "$(dirname "$0")" && pwd)"
GRAPH="${GRAPH_MD:-$SDIR/graph.md}"
HOOKS="${GRAPH_HOOKS:-$(cd "$SDIR/../../hooks" 2>/dev/null && pwd)}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "git 저장소 안에서 실행하세요." >&2; exit 1; }
cd "$ROOT" || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NT="$T/nodes"; FP="$T/fails"; CT="$T/checklist"; KV="$T/kv"; AP="$T/ap"; LG="$T/lg"
: > "$KV"; : > "$AP"; : > "$LG"

NOW() { date '+%Y-%m-%d %H:%M'; }
say() { printf '%s\n' "$*"; }
die() { local c="$1"; shift; printf '%s\n' "$*" >&2; exit "$c"; }
# 사장 답·이유: 따옴표·역슬래시·탭·줄바꿈을 지우고 낱말 단위로 200바이트 안쪽만(글자 중간에서 자르지 않음)
clean() { printf '%s' "$1" | tr '\t\r\n"\\' '     ' | awk '{s=""; for(i=1;i<=NF;i++){ if (length(s)+length($i)>200) break; s=s (s==""?"":" ") $i } print s}'; }
STATUSES="대기 진행 통과 실패 승인 사장대기 사장보고 도구없음 건너뜀 확인필요"

# ---------------- graph.md 읽기 ----------------
table() { # 표 시작 표시, 끝 표시 → 칸을 탭으로 이은 줄 (머리·구분 줄 제외)
  awk -v s="<!-- $1:start -->" -v e="<!-- $1:end -->" '
    index($0, s) { f=1; next } index($0, e) { f=0 }
    f && /^\|/ { n=split($0, a, "|"); out=""
      for (i=2; i<n; i++) { c=a[i]; gsub(/^[ \t]+|[ \t]+$/, "", c); out=out (i>2 ? "\t" : "") c }
      split(out, b, "\t"); if (b[1]=="id" || b[1]=="출발" || b[1]=="#" || b[1] ~ /^-+$/) next; print out }' "$GRAPH"
}
[ -f "$GRAPH" ] || die 1 "graph.md가 없습니다: $GRAPH"
table nodes > "$NT"
table fails | awk -F'\t' 'BEGIN{OFS="\t"} { n=split($1,f,","); m=split($3,t,",")
  for(i=1;i<=n;i++) for(j=1;j<=m;j++) print f[i], t[j], $4, $5, $2 }' > "$FP"
table checklist > "$CT"
[ -s "$NT" ] || die 1 "graph.md 노드 표를 읽지 못했습니다."
# 칸: 1 id 2 이름 3 종류 4 담당 5 받는 것 6 내는 것 7 통과 조건 8 검사 9 다음 10 다시 11 합류 12 실패 시 13 최대 14 건너뛰기 15 옛 단계
nf() { awk -F'\t' -v id="$1" -v k="$2" '$1==id { print $k; exit }' "$NT"; }
is_node() { awk -F'\t' -v id="$1" '$1==id { f=1 } END { exit f?0:1 }' "$NT"; }
ids() { cut -f1 "$NT"; }
nname() { nf "$1" 2; }
order_of() { awk -F'\t' -v id="$1" '$1==id { print NR; exit }' "$NT"; }

# ---------------- 상태(KV) ----------------
kget() { awk -F'\t' -v k="$1" '$1==k { print $2; exit }' "$KV"; }
kset() { awk -F'\t' -v k="$1" -v v="$2" 'BEGIN{OFS="\t"} $1==k { print k, v; f=1; next } { print } END { if (!f) print k, v }' "$KV" > "$KV.t" && mv "$KV.t" "$KV"; }
st() { local v; v="$(kget "n.$1.status")"; printf '%s' "${v:-대기}"; }
setst() { kset "n.$1.status" "$2"; }
nnum() { local v; v="$(kget "n.$1.$2")"; printf '%s' "${v:-0}"; }
in_list() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }
cur() { kget current; }
in_cur() { in_list "$1" "$(cur)"; }
cur_add() { local c; c="$(cur)"; in_list "$1" "$c" && return; kset current "${c:+$c,}$1"; }
cur_del() { kset current "$(cur | tr ',' '\n' | grep -vx "$1" | paste -sd, -)"; }
log_add() { printf '%s\t%s\t%s\t%s\t%s\n' "$(NOW)" "$1" "$2" "$3" "$(clean "$4")" >> "$LG"; }
set_wait() { kset wait.node "$1"; kset wait.kind "$2"; kset wait.line "$(clean "$3")"; }
clear_wait() { [ "$(kget wait.node)" = "$1" ] && { kset wait.node ""; kset wait.kind ""; kset wait.line ""; }; return 0; }
locked_before() { awk -F'\t' '$2=="lock" { f=1 } END { exit f?0:1 }' "$LG"; }
has_approval() { awk -F'\t' -v n="$1" '$1==n { f=1 } END { exit f?0:1 }' "$AP"; }

# ---------------- 앱·state.json ----------------
set_app() {
  [ -n "$1" ] || die 1 "앱을 주세요: apps/<앱>"
  APP="${1%/}"; APP="${APP#apps/}"; APP="${APP##*/}"
  printf '%s' "$APP" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || die 1 "앱 이름은 영문 소문자·숫자·하이픈만: $APP"
  APPDIR="apps/$APP"; STATE="$APPDIR/state.json"
}
broken() { die 3 "[그래프 $APP] state.json이 깨졌습니다($STATE): $1
추측해서 고치지 말고 사장에게 알리세요. (graph.sh는 깨진 파일을 고치지 않습니다)"; }

parse_state() {
  [ -f "$STATE" ] || die 1 "[그래프 $APP] state.json이 없습니다. 새 앱: graph.sh init $APPDIR / 그래프 이전 앱: graph.sh migrate $APPDIR"
  [ -s "$STATE" ] || broken "빈 파일"
  local err
  err="$(tr -d '\r' < "$STATE" | awk -v KV="$KV" -v AP="$AP" -v LG="$LG" '
    function sk(s) { gsub(/"[^"]*"/, "Q", s); gsub(/[0-9]+/, "N", s); return s }
    function strs(s,   n) { n=0; while (match(s, /"[^"]*"/)) { S[++n]=substr(s, RSTART+1, RLENGTH-2); s=substr(s, RSTART+RLENGTH) } return n }
    function nums(s,   n) { gsub(/"[^"]*"/, "", s); n=0; while (match(s, /[0-9]+/)) { N[++n]=substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH) } return n }
    function bad(m) { print "줄 " NR ": " m > "/dev/stderr"; err=1; exit 1 }
    function kv(k, v) { print k "\t" v > KV }
    function lst(s,   n, i, o) { n=strs(s); o=""; for (i=2; i<=n; i++) o=o (i>2 ? "," : "") S[i]; return o }
    NR==1 { if ($0 != "{") bad("첫 줄이 { 가 아님"); next }
    sec=="nodes" {
      if ($0 == "  },") { sec=""; next }
      k=sk($0); if (k !~ /^    Q: \{Q: Q, Q: N, Q: N, Q: N, Q: N, Q: N, Q: Q\},?$/) bad("노드 줄 형식")
      strs($0); nums($0); id=S[1]
      if (S[2]!="status" || S[3]=="" ) bad("노드 줄 키")
      kv("n." id ".status", S[3]); kv("n." id ".retries", N[1]); kv("n." id ".boss_fixes", N[2])
      kv("n." id ".rounds", N[3]); kv("n." id ".same", N[4]); kv("n." id ".rmax", N[5]); kv("n." id ".sig", S[10])
      print "NODE\t" id; next }
    sec=="ap" {
      if ($0 == "  ],") { sec=""; next }
      if (sk($0) !~ /^    \{Q: Q, Q: Q, Q: Q\},?$/) bad("approvals 줄 형식")
      strs($0); if (S[1]!="node" || S[3]!="at" || S[5]!="answer") bad("approvals 키")
      print S[2] "\t" S[4] "\t" S[6] > AP; next }
    sec=="lg" {
      if ($0 == "  ]") { sec="end"; next }
      if (sk($0) !~ /^    \{Q: Q, Q: Q, Q: Q, Q: Q, Q: Q\},?$/) bad("log 줄 형식")
      strs($0); if (S[1]!="at" || S[3]!="do") bad("log 키")
      print S[2] "\t" S[4] "\t" S[6] "\t" S[8] "\t" S[10] > LG; next }
    sec=="end" { if ($0 != "}") bad("끝 줄이 } 가 아님"); sec="closed"; next }
    sec=="closed" { if ($0 != "") bad("} 뒤에 글자가 있음"); next }
    {
      k=sk($0)
      if (k == "  Q: N,") { strs($0); nums($0); if (S[1]!="version" || N[1]!="1") bad("version"); kv("version", 1); seen["version"]=1; next }
      if (k == "  Q: [],") { strs($0); if (S[1]=="approvals") { seen["approvals"]=1; next } }
      if (k ~ /^  Q: \[(Q(, Q)*)?\],$/) { strs($0); if (S[1]!="current" && S[1]!="queue") bad("목록 키"); kv(S[1], lst($0)); seen[S[1]]=1; next }
      if (k == "  Q: Q,") { strs($0); if (S[1]!="app" && S[1]!="resume" && S[1]!="ex_budget") bad("키 " S[1]); kv(S[1], S[2]); seen[S[1]]=1; next }
      if (k == "  Q: {Q: Q, Q: Q, Q: Q},") { strs($0); if (S[1]!="wait") bad("wait"); kv("wait.node", S[3]); kv("wait.kind", S[5]); kv("wait.line", S[7]); seen["wait"]=1; next }
      if (k == "  Q: {Q: Q, Q: Q, Q: Q, Q: Q},") { strs($0); if (S[1]!="last_fail") bad("last_fail"); kv("lf.from", S[3]); kv("lf.to", S[5]); kv("lf.reason", S[7]); kv("lf.at", S[9]); seen["last_fail"]=1; next }
      if (k == "  Q: {Q: N, Q: Q, Q: Q},") { strs($0); nums($0); if (S[1]!="score") bad("score"); kv("score.rounds", N[1]); kv("score.history", S[4]); kv("score.last", S[6]); seen["score"]=1; next }
      if (k == "  Q: {") { strs($0); if (S[1]!="nodes") bad("nodes"); sec="nodes"; seen["nodes"]=1; next }
      if (k == "  Q: [],") { strs($0); if (S[1]!="approvals") bad("approvals"); seen["approvals"]=1; next }
      if (k == "  Q: [") { strs($0); if (S[1]=="approvals") { sec="ap"; seen["approvals"]=1; next } if (S[1]=="log") { sec="lg"; seen["log"]=1; next } bad("목록") }
      if (k == "  Q: []") { strs($0); if (S[1]!="log") bad("log"); seen["log"]=1; sec="end"; next }
      bad("알 수 없는 줄")
    }
    END { if (err) exit 1
      if (sec!="closed") { print "파일이 중간에 끝남" > "/dev/stderr"; exit 1 }
      split("version app current queue resume wait last_fail ex_budget score nodes approvals log", need, " ")
      for (i in need) if (!(need[i] in seen)) { print "빠진 키: " need[i] > "/dev/stderr"; exit 1 } }' 2>&1 >"$T/parsed")" || broken "$(printf '%s' "$err" | head -n1)"
  local id
  err="$(awk -F'\t' -v ok="$STATUSES" '
    FILENAME==ARGV[1] { node[$1]=1; next }
    FILENAME==ARGV[2] { kv[$1]=$2; next }
    $1=="NODE" { id=$2; if (!(id in node)) { print "graph.md에 없는 노드: " id; exit 1 }
      s=kv["n." id ".status"]; if (index(" " ok " ", " " s " ")==0) { print "모르는 상태 값: " id " = " s; exit 1 } }
    END { n=split(kv["current"] "," kv["queue"] "," kv["resume"], a, ",")
      for (i=1; i<=n; i++) if (a[i]!="" && !(a[i] in node)) { print "current/queue/resume에 없는 노드: " a[i]; exit 1 } }' \
    "$NT" "$KV" "$T/parsed")" || broken "$err"
  [ "$(kget app)" = "$APP" ] || broken "app 이름이 폴더와 다름: $(kget app)"
  # 잠금 기록이 있는데 잠금 파일이 사라졌으면 멈춘다(지우고 다시 자동 잠그는 길 차단)
  if locked_before; then
    bash "$HOOKS/check-approved.sh" lock "$APPDIR" </dev/null >/dev/null 2>&1
    [ $? -eq 1 ] && broken "잠금 기록(log의 lock)이 있는데 테스트 잠금 파일이 없습니다"
  fi
  return 0
}

jlist() { [ -z "$1" ] && return; printf '%s' "$1" | awk -F, '{ for (i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?", ":""), $i }'; }
write_state() {
  local id last n
  last="$(ids | tail -n1)"
  {
    echo "{"
    echo "  \"version\": 1,"
    echo "  \"app\": \"$APP\","
    echo "  \"current\": [$(jlist "$(cur)")],"
    echo "  \"queue\": [$(jlist "$(kget queue)")],"
    echo "  \"resume\": \"$(kget resume)\","
    echo "  \"wait\": {\"node\": \"$(kget wait.node)\", \"kind\": \"$(kget wait.kind)\", \"line\": \"$(kget wait.line)\"},"
    echo "  \"last_fail\": {\"from\": \"$(kget lf.from)\", \"to\": \"$(kget lf.to)\", \"reason\": \"$(kget lf.reason)\", \"at\": \"$(kget lf.at)\"},"
    echo "  \"ex_budget\": \"$(kget ex_budget)\","
    n="$(kget score.rounds)"
    echo "  \"score\": {\"rounds\": ${n:-0}, \"history\": \"$(kget score.history)\", \"last\": \"$(kget score.last)\"},"
    echo "  \"nodes\": {"
    awk -F'\t' 'NR==FNR { kv[$1]=$2; next } { ids[++n]=$1 }
      function num(k) { return (k in kv && kv[k]!="") ? kv[k] : 0 }
      END { for (i=1; i<=n; i++) { id=ids[i]; s=kv["n." id ".status"]; if (s=="") s="대기"
        printf "    \"%s\": {\"status\": \"%s\", \"retries\": %s, \"boss_fixes\": %s, \"rounds\": %s, \"same\": %s, \"rmax\": %s, \"sig\": \"%s\"}%s\n", \
          id, s, num("n." id ".retries"), num("n." id ".boss_fixes"), num("n." id ".rounds"), num("n." id ".same"), num("n." id ".rmax"), kv["n." id ".sig"], (i<n ? "," : "") } }' "$KV" "$NT"
    echo "  },"
    if [ -s "$AP" ]; then
      echo "  \"approvals\": ["
      awk -F'\t' '{ a[NR]=sprintf("    {\"node\": \"%s\", \"at\": \"%s\", \"answer\": \"%s\"}", $1, $2, $3) } END { for (i=1;i<=NR;i++) print a[i] (i<NR?",":"") }' "$AP"
      echo "  ],"
    else
      echo "  \"approvals\": [],"
    fi
    if [ -s "$LG" ]; then
      echo "  \"log\": ["
      awk -F'\t' '{ a[NR]=sprintf("    {\"at\": \"%s\", \"do\": \"%s\", \"node\": \"%s\", \"to\": \"%s\", \"note\": \"%s\"}", $1, $2, $3, $4, $5) } END { for (i=1;i<=NR;i++) print a[i] (i<NR?",":"") }' "$LG"
      echo "  ]"
    else
      echo "  \"log\": []"
    fi
    echo "}"
  } > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  update_handoff
}

# 앱 HANDOFF.md 의 "현재 단계:" 줄을 state.json 에 맞춘다
update_handoff() {
  local h="$APPDIR/HANDOFF.md" line c id parts=""
  [ -f "$h" ] && grep -q '^현재 단계:' "$h" || return 0
  c="$(cur)"
  if [ -z "$c" ] && [ "$(st done)" = "통과" ]; then
    line="현재 단계: 완료 (그래프 끝, state.json)"
  else
    for id in $(printf '%s' "$c" | tr ',' ' '); do parts="${parts:+$parts, }$id $(nname "$id")($(st "$id"))"; done
    line="현재 단계: ${parts:-없음} — 그래프 state.json"
  fi
  awk -v l="$line" '!d && /^현재 단계:/ { print l; d=1; next } { print }' "$h" > "$h.t" && mv "$h.t" "$h"
}

# ---------------- 프로그램 검사 ----------------
run_tests() { # [백엔드]
  local out rc
  out="$(bash "$HOOKS/check-tests.sh" app "$APPDIR" $1 </dev/null 2>&1)"; rc=$?
  [ -d "$APPDIR/docs" ] && printf '%s\n' "$out" > "$APPDIR/docs/test-log.txt"
  TEST_OUT="$out"
  return $rc
}
lock_ok() { bash "$HOOKS/check-approved.sh" lock "$APPDIR" </dev/null >/dev/null 2>&1; }
has_server() { [ "$(st bb)" != "건너뜀" ]; }
has_screen() { [ "$(st ui)" != "건너뜀" ]; }
perf_items() { # 줄마다: 이름 기준 비교(le|eq) 담당
  has_screen && printf 'LCP 2.5 le bf\nCLS 0.1 le bf\n콘솔에러 0 eq bf\n실패요청 0 eq bf\n'
  has_server && printf '부하에러율 0 eq bb\np99 1 le bb\n'
}
perf_check() { # 결과: 줄마다 "ok|fail 이름 담당 설명"
  local f="$APPDIR/docs/perf.txt"
  perf_items | while read -r k lim op own; do
    v="$( [ -f "$f" ] && awk -v k="$k" '$1==k { print $2; exit }' "$f")"
    if [ -z "$v" ]; then echo "fail $k $own 값 없음"; continue; fi
    awk -v v="$v" -v l="$lim" -v op="$op" 'BEGIN { if (v !~ /^[0-9.]+$/) exit 1; if (op=="le") exit !(v+0<=l+0); exit !(v+0==l+0) }' \
      && echo "ok $k $own $v" || echo "fail $k $own $v(기준 $lim)"
  done
}
redteam_ok() { [ ! -f "$APPDIR/.redteam-needed" ] && [ -f "$APPDIR/docs/redteam.md" ]; }
secrets_ok() { SECRET_OUT="$(bash "$HOOKS/guard-git.sh" scan "$APPDIR" </dev/null 2>&1)"; }
run_check() { # 노드의 ⚙️ 검사. 실패면 CHECK_MSG 와 함께 1
  local key; key="$(nf "$1" 8)"; CHECK_MSG=""
  case "$key" in
    -|"") return 0 ;;
    lock) lock_ok || { CHECK_MSG="테스트 잠금 파일이 없거나 해시가 다릅니다."; return 1; } ;;
    backend) run_tests 백엔드 || { CHECK_MSG="백엔드 테스트 실패:
$(printf '%s\n' "$TEST_OUT" | tail -n 15)"; return 1; } ;;
    tests) run_tests || { CHECK_MSG="테스트 실패:
$(printf '%s\n' "$TEST_OUT" | tail -n 15)"; return 1; }
           lock_ok || { CHECK_MSG="승인된 테스트 해시가 다릅니다(사장 허락 없이 바뀜)."; return 1; } ;;
    perf) local r; r="$(perf_check)"; printf '%s\n' "$r" | grep -q '^fail' && { CHECK_MSG="수치 미달: $(printf '%s\n' "$r" | grep '^fail' | cut -d' ' -f2,4- | paste -sd, -)"; return 1; } ;;
    redteam) redteam_ok || { CHECK_MSG=".redteam-needed 표시가 남아 있거나 docs/redteam.md가 없습니다."; return 1; } ;;
    secrets) secrets_ok || { CHECK_MSG="비밀값 검사에 걸렸습니다:
$SECRET_OUT"; return 1; } ;;
    score) CHECK_MSG="sc는 graph.sh score 로만 통과합니다."; return 1 ;;
    *) CHECK_MSG="graph.md의 모르는 검사: $key"; return 1 ;;
  esac
  return 0
}

# ---------------- 이동 ----------------
relock_line() { sed -n 's/.*<!-- relock: \(.*\) -->.*/\1/p' "$GRAPH" | head -n1 | sed "s#<앱>#$APP#"; }
first_opt() { printf '%s' "$1" | tr '+,' '  ' | awk '{ print $1 }'; }
last_opt() { printf '%s' "$1" | tr '+,' '  ' | awk '{ print $NF }'; }
opts() { printf '%s' "$1" | tr '+,' '  '; }

# 노드에 들어간다: 합류 조건 확인 → 건너뜀이면 지나감 → 종류별 상태
enter() {
  local id="$1" j p kind
  j="$(nf "$id" 11)"
  if [ -n "$j" ] && [ "$j" != "-" ]; then
    for p in $(opts "$j"); do case "$(st "$p")" in 통과|건너뜀) ;; *) return 0 ;; esac; done
  fi
  if [ "$(st "$id")" = "건너뜀" ]; then follow "$id"; return 0; fi
  in_cur "$id" && return 0
  kind="$(nf "$id" 3)"
  case "$kind" in
    끝) setst "$id" 통과; log_add end "$id" "" ""; return 0 ;;
  esac
  cur_add "$id"
  case "$kind" in
    사람)
      setst "$id" "사장대기"
      local w; w="$(nname "$id") — AskUserQuestion으로 보기 + 추천을 붙여 묻고 답을 approve"
      if [ "$id" = "pub" ]; then
        if secrets_ok; then w="$w (비밀값 검사 통과)"; else w="$w (비밀값 검사에 걸림 — 먼저 사장에게 알리기)"; fi
      fi
      set_wait "$id" "①" "$w" ;;
    *) setst "$id" "진행"
       case "$id" in bb|bf) kset "n.$id.rounds" 0; kset "n.$id.same" 0; kset "n.$id.sig" "" ;; esac ;;
  esac
  case "$id" in
    lock) do_lock ;;
    ex) if [ "$(kget ex_budget)" = "0" ]; then
          setst ex "건너뜀"; cur_del ex; log_add skip ex "" "건너뜀(사장 선택)"; follow ex
        fi ;;
  esac
  return 0
}
# 건너뛴 노드를 지나간다: 동시면 모두, 고르는 길이면 마지막 길로
follow() {
  local nx t; nx="$(nf "$1" 9)"; [ "$nx" = "-" ] && return 0
  case "$nx" in *+*) for t in $(opts "$nx"); do enter "$t"; done ;; *) enter "$(last_opt "$nx")" ;; esac
}
do_lock() {
  local rc
  write_state   # auto-lock.sh 가 디스크의 state.json(tc 통과·ok-tl 승인)을 읽으므로 먼저 저장
  bash "$HOOKS/check-approved.sh" lock "$APPDIR" </dev/null >/dev/null 2>&1; rc=$?
  if [ $rc -eq 1 ] && ! locked_before; then
    if LOCK_OUT="$(bash "$HOOKS/auto-lock.sh" "$APPDIR" </dev/null 2>&1)"; then
      log_add lock lock "" "첫 잠금 자동(auto-lock.sh)"; advance lock ""; return 0
    fi
    setst lock "사장보고"; set_wait lock "②" "자동 잠금 실패: $(printf '%s' "$LOCK_OUT" | tail -n1)"; return 0
  fi
  if [ $rc -eq 0 ]; then log_add lock-ok lock "" "잠금 그대로(해시 일치)"; advance lock ""; return 0; fi
  # 승인된 테스트가 바뀌어 다시 잠가야 함 → 사장만(⑤)
  setst lock "사장대기"; set_wait lock "⑤" "승인된 테스트를 다시 잠가야 합니다. 사장이 붙여 넣을 한 줄: $(relock_line)"
}
# 통과 뒤 다음 노드 정하기 (선택 확인은 호출 전에)
next_targets() { # id → NEXT_LIST (공백), NEXT_KIND(normal|rework|resume|queue)
  local id="$1" res q rw nx
  res="$(kget resume)"; q="$(kget queue)"; rw="$(nf "$id" 10)"
  if [ -n "$res" ] && [ "$rw" != "-" ] && [ -n "$rw" ]; then
    if [ -n "$q" ] && { [ "$id" = bb ] || [ "$id" = bf ]; }; then NEXT_LIST="$(first_opt "$q")"; NEXT_KIND=queue
    else NEXT_LIST="$(opts "$rw")"; NEXT_KIND=rework; fi
    return
  fi
  if [ "$id" = tr ] && [ -n "$res" ] && [ "$res" != tr ]; then NEXT_LIST="$res"; NEXT_KIND=resume; return; fi
  nx="$(nf "$id" 9)"; NEXT_KIND=normal
  case "$nx" in
    -) NEXT_LIST="" ;;
    *+*) NEXT_LIST="$(opts "$nx")" ;;
    *,*) NEXT_LIST="CHOOSE:$nx" ;;
    *) NEXT_LIST="$nx" ;;
  esac
}
advance() { # id, 고른 다음
  local id="$1" choice="$2" t
  next_targets "$id"
  case "$NEXT_LIST" in
    CHOOSE:*) local o="${NEXT_LIST#CHOOSE:}"
      [ -n "$choice" ] || die 1 "[그래프 $APP] $id 다음 길을 고르세요: graph.sh pass $APPDIR $id <$(printf '%s' "$o" | tr ',' '|')>"
      in_list "$choice" "$o" || die 1 "[그래프 $APP] $id 다음은 $o 중 하나입니다(받은 값: $choice)"
      NEXT_LIST="$choice" ;;
  esac
  setst "$id" 통과; cur_del "$id"; clear_wait "$id"
  case "$NEXT_KIND" in
    queue) local q; q="$(kget queue)"; case "$q" in *,*) kset queue "${q#*,}" ;; *) kset queue "" ;; esac ;;
    resume) kset resume "" ;;
  esac
  [ "$id" = tr ] && [ "$(kget resume)" = tr ] && kset resume ""
  log_add pass "$id" "$(printf '%s' "$NEXT_LIST" | tr ' ' ',')" "$NEXT_KIND"
  for t in $NEXT_LIST; do
    [ "$(st "$t")" = "건너뜀" ] || { [ "$(st "$t")" = "통과" ] && setst "$t" 대기; }
    enter "$t"
  done
}

# ---------------- 명령 ----------------
need_cur() { in_cur "$1" || die 1 "[그래프 $APP] $1 은(는) 지금 노드가 아닙니다. 현재: $(cur | sed 's/^$/없음/')"; }

cmd_pass() {
  local id="$1" choice="$2" s kind
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"
  s="$(st "$id")"
  if ! in_cur "$id"; then
    [ "$s" = "통과" ] && { say "[그래프 $APP] $id 는 이미 통과 — 기록은 그대로 둡니다."; exit 0; }
    need_cur "$id"
  fi
  kind="$(nf "$id" 3)"
  case "$s" in 사장보고|도구없음) die 1 "[그래프 $APP] $id 는 '$s' 상태입니다. 사장 답을 받은 뒤 graph.sh resume $APPDIR $id" ;; esac
  if [ "$kind" = "사람" ]; then
    [ "$s" = "승인" ] || die 1 "[그래프 $APP] ★ 노드 $id 는 사장 답(approve) 없이 pass할 수 없습니다."
    [ "$id" = ok-ip ] && [ -z "$(kget ex_budget)" ] && die 1 "[그래프 $APP] ok-ip: 탐색·사용성 점검 예상 비용을 알리고 답을 graph.sh budget $APPDIR <예상 토큰|0> 으로 먼저 적으세요."
  elif [ "$s" = "사장대기" ] && [ "$id" != lock ]; then
    die 1 "[그래프 $APP] $id 는 사장 대기입니다. 사장 답을 받은 뒤 graph.sh resume $APPDIR $id"
  fi
  run_check "$id" || die 1 "[그래프 $APP] $id 통과 검사 실패 — $CHECK_MSG
(실패면: graph.sh fail $APPDIR $id \"<이유>\" [보낼 곳])"
  if locked_before && [ "$(nf "$id" 8)" != lock ]; then
    lock_ok || die 1 "[그래프 $APP] 승인된 테스트 해시가 다릅니다. 승인 테스트는 사장 허락 없이 바꾸지 않습니다 — 되돌리거나 사장에게 알리세요."
  fi
  advance "$id" "$choice"
  write_state
  status_short
}

cmd_fail() {
  local id="$1" reason="$2" targets="$3" allowed t kind after res first rest r mx
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"
  need_cur "$id"
  [ -n "$reason" ] || die 1 "실패 이유를 주세요: graph.sh fail $APPDIR $id \"<이유>\" [보낼 곳]"
  allowed="$(awk -F'\t' -v f="$id" '$1==f { print $2 }' "$FP" | paste -sd, -)"
  [ -n "$allowed" ] || die 1 "[그래프 $APP] $id 에서 나가는 실패 엣지가 graph.md 표에 없습니다. 구현 전이면 사장에게 보기 + 추천으로 묻고, 구현~QA 보고 사이면 docs/ask-later.md에 적으세요."
  if [ -z "$targets" ]; then
    case "$allowed" in *,*) die 1 "[그래프 $APP] 보낼 곳을 고르세요: graph.sh fail $APPDIR $id \"$reason\" <$allowed 중>" ;; esac
    targets="$allowed"
  fi
  for t in $(opts "$targets"); do
    in_list "$t" "$allowed" || die 1 "[그래프 $APP] 표에 없는 실패 엣지: $id → $t (가능: $allowed). 사장에게 보기 + 추천으로 묻거나 docs/ask-later.md에 적으세요."
    [ "$(st "$t")" = "건너뜀" ] && die 1 "[그래프 $APP] $t 는 건너뛴 노드입니다(이 앱에 없음)."
  done
  # bb 먼저, 그다음 bf … (graph.md 순서)
  targets="$(for t in $(opts "$targets"); do printf '%s %s\n' "$(order_of "$t")" "$t"; done | sort -n | awk '{ print $2 }' | paste -sd, -)"
  kind="$(nf "$id" 3)"
  if [ "$kind" = "사람" ]; then
    r=$(( $(nnum "$id" boss_fixes) + 1 )); kset "n.$id.boss_fixes" "$r"
    [ $r -ge 3 ] && say "[그래프 $APP] $id 사장 수정 지시 ${r}번째 — 같은 지적 반복이면 '방식을 바꾸자' 보기 2~3개 + 추천을 내세요(거부하지 않음)."
  else
    for t in $(opts "$targets"); do
      r=$(( $(nnum "$t" retries) + 1 )); mx="$(nf "$t" 13)"
      if printf '%s' "$mx" | grep -Eq '^[0-9]+$' && [ $r -gt "$mx" ]; then
        setst "$id" "사장보고"; set_wait "$id" "②" "$t 로 되돌아간 횟수가 한도 $mx 를 넘음. 이유: $reason"
        log_add over "$id" "$t" "$reason"; write_state
        die 4 "[그래프 $APP] $t 로 되돌아간 횟수가 한도($mx)를 넘었습니다 → 사장 보고 상태. 무엇이·왜 막혔는지와 보기 2~3개 + 추천으로 보고하세요."
      fi
      kset "n.$t.retries" "$r"
    done
  fi
  first="$(first_opt "$targets")"
  after="$(awk -F'\t' -v f="$id" -v t="$first" '$1==f && $2==t { print $3; exit }' "$FP")"
  case "$after" in
    @self) res="$id" ;;
    @next) res="$(first_opt "$(nf "$id" 9)")" ;;
    @normal|"") res="" ;;
    *) res="$after" ;;
  esac
  if [ "$after" = "@normal" ]; then kset resume ""; kset queue ""
  elif [ -z "$(kget resume)" ]; then kset resume "$res"; fi
  setst "$id" "실패"; cur_del "$id"; clear_wait "$id"
  kset lf.from "$id"; kset lf.to "$targets"; kset lf.reason "$(clean "$reason")"; kset lf.at "$(NOW)"
  log_add fail "$id" "$targets" "$reason"
  rest="$(printf '%s' "$targets" | cut -s -d, -f2-)"
  if [ -n "$rest" ]; then
    kset queue "$(printf '%s' "$(kget queue)${rest:+,$rest}" | sed 's/^,//')"
    for t in $(opts "$rest"); do setst "$t" 대기; done
  fi
  setst "$first" 대기
  enter "$first"
  write_state
  say "[그래프 $APP] $id 실패 → $targets (고친 뒤: ${after:-@normal}${res:+ → $res})"
  status_short
}

cmd_approve() {
  local id="$1" ans="$2"
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"
  [ "$(nf "$id" 3)" = "사람" ] || die 1 "[그래프 $APP] $id 는 ★ 노드가 아닙니다."
  need_cur "$id"
  [ "$(st "$id")" = "승인" ] && { say "[그래프 $APP] $id 는 이미 승인 — 그대로 둡니다."; exit 0; }
  [ -n "$ans" ] || die 1 "사장 답을 그대로 짧게 주세요: graph.sh approve $APPDIR $id \"<사장 답>\""
  printf '%s\t%s\t%s\n' "$id" "$(NOW)" "$(clean "$ans")" >> "$AP"
  setst "$id" "승인"; clear_wait "$id"; log_add approve "$id" "" "$ans"
  write_state
  say "[그래프 $APP] $id 승인 기록: $(clean "$ans") → graph.sh pass $APPDIR $id"
}

cmd_wait() {
  local id="$1" line="$2"
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"; need_cur "$id"
  [ -n "$line" ] || line="$(relock_line)"
  setst "$id" "사장대기"; set_wait "$id" "⑤" "$line"; log_add wait "$id" "" "$line"
  write_state; say "[그래프 $APP] $id 사장 대기(⑤): $line"
}
cmd_stuck() {
  local id="$1" k="$2" msg="$3"
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"; need_cur "$id"
  case "$k" in 도구) setst "$id" "도구없음"; set_wait "$id" "③" "$msg" ;; 보고) setst "$id" "사장보고"; set_wait "$id" "②" "$msg" ;;
    *) die 1 "종류는 도구 또는 보고: graph.sh stuck $APPDIR $id 도구|보고 \"<내용>\"" ;; esac
  log_add stuck "$id" "$k" "$msg"; write_state; say "[그래프 $APP] $id 멈춤($k): $msg"
}
cmd_resume() {
  local id="$1"
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"; need_cur "$id"
  [ "$(nf "$id" 3)" = "사람" ] && die 1 "[그래프 $APP] ★ 노드는 resume이 아니라 approve 입니다."
  case "$(st "$id")" in 사장대기|사장보고|도구없음) ;; *) die 1 "[그래프 $APP] $id 는 멈춘 상태가 아닙니다($(st "$id"))." ;; esac
  setst "$id" "진행"; clear_wait "$id"
  case "$id" in bb|bf) kset "n.$id.rounds" 0; kset "n.$id.same" 0; kset "n.$id.sig" "" ;; esac
  log_add resume "$id" "" ""; write_state; say "[그래프 $APP] $id 다시 진행"
}
cmd_skip() {
  local list="$1" reason="${2:-건너뜀}" id
  for id in $(opts "$list"); do
    is_node "$id" || die 1 "graph.md에 없는 노드: $id"
    [ "$(nf "$id" 14)" != "-" ] || die 1 "[그래프 $APP] $id 는 건너뛸 수 없는 노드입니다(graph.md 건너뛰기 칸)."
    case "$(st "$id")" in 대기|진행|사장대기) ;; 건너뜀) continue ;; *) die 1 "[그래프 $APP] $id 는 지금 건너뛸 수 없습니다($(st "$id"))." ;; esac
  done
  for id in $(opts "$list"); do
    [ "$(st "$id")" = "건너뜀" ] && continue
    setst "$id" "건너뜀"; log_add skip "$id" "" "$reason"
    if in_cur "$id"; then cur_del "$id"; clear_wait "$id"; follow "$id"; fi
  done
  write_state; say "[그래프 $APP] 건너뜀: $list ($reason)"; status_short
}
cmd_budget() {
  printf '%s' "$1" | grep -Eq '^[0-9]+$' || die 1 "예상 토큰 수(숫자, 건너뛰기는 0): graph.sh budget $APPDIR <토큰>"
  kset ex_budget "$1"; log_add budget ex "" "$1"; write_state
  say "[그래프 $APP] 탐색·사용성 예상: $([ "$1" = 0 ] && echo '건너뛰기(사장 선택)' || echo "$1 토큰")"
}
cmd_usage() {
  local u="$1" b
  printf '%s' "$u" | grep -Eq '^[0-9]+$' || die 1 "실제 사용 토큰(숫자)"
  need_cur ex; b="$(kget ex_budget)"
  if [ -n "$b" ] && [ "$b" -gt 0 ] && [ "$u" -gt $((b * 2)) ]; then
    setst ex "사장대기"; set_wait ex "④" "탐색·사용성 사용량 $u 가 예상 $b 의 2배를 넘음 — 계속할지 묻기"
    log_add usage ex "" "$u > 2x $b"; write_state
    say "[그래프 $APP] ④ 사용량이 예상의 2배를 넘었습니다($u > 2×$b). 멈추고 계속할지 사장에게 묻으세요."; return 0
  fi
  say "[그래프 $APP] 탐색·사용성 사용량 $u (예상 $b) — 계속"
}

# 구현 노드 자동 루프 (graph-stop.sh 가 부름)
cmd_loop() {
  local id="" c out sig r sm
  for c in bb bf; do in_cur "$c" && [ "$(st "$c")" = "진행" ] && { id="$c"; break; }; done
  [ -z "$id" ] && exit 0
  if run_check "$id" && { ! locked_before || lock_ok; }; then
    advance "$id" ""; write_state
    say "[그래프 $APP·$id] 통과(⚙️ $(nf "$id" 7)). 다음 노드 $(cur | sed 's/^$/없음/')를 시작하세요. progress.md에 마지막 회차를 적으세요."
    exit 21
  fi
  [ -z "$CHECK_MSG" ] && CHECK_MSG="승인된 테스트 해시가 다릅니다."
  r=$(( $(nnum "$id" rounds) + 1 )); kset "n.$id.rounds" "$r"
  sig="$(printf '%s\n' "$CHECK_MSG" | grep -Ei 'fail|✘|✗|error|expected|assert|실패|다릅니다' | sed 's/[0-9]\{1,\}//g; s/[[:space:]]\{1,\}/ /g' | sort | cksum | cut -d' ' -f1)"
  if [ "$sig" = "$(kget "n.$id.sig")" ]; then sm=$(( $(nnum "$id" same) + 1 )); else sm=1; fi
  kset "n.$id.same" "$sm"; kset "n.$id.sig" "$sig"
  [ "$r" -gt "$(nnum "$id" rmax)" ] && kset "n.$id.rmax" "$r"
  if [ "$r" -gt 15 ] || [ "$sm" -ge 3 ]; then
    setst "$id" "사장보고"
    set_wait "$id" "②" "자동 루프 브레이크: $([ "$r" -gt 15 ] && echo "15회 초과" || echo "같은 실패 3회 연속")"
    log_add brake "$id" "" "회차 $r, 같은 실패 $sm"; write_state
    say "[그래프 $APP·$id] 브레이크($([ "$r" -gt 15 ] && echo "15회 초과" || echo "같은 실패 3회 연속")). 고치기를 멈추고 사장에게 보고하세요: 무엇이·왜 막혔는지 + 보기 2~3개 + 추천. (superpowers:systematic-debugging 결과 포함)
$CHECK_MSG"
    exit 22
  fi
  log_add round "$id" "" "회차 $r 실패"; write_state
  say "[그래프 $APP·$id] 회차 $r 실패(같은 실패 ${sm}회 연속) — 계속 고치세요. 회차를 docs/progress.md에 적으세요(회차 | 한 일 | 테스트 N/N | 실패와 이유 | 다음 시도).
$CHECK_MSG"
  exit 20
}

# 완성도 점수 (sc)
evid_ok() { # "파일:줄" (앱 폴더 기준)이 실제로 있는지
  local f="${1%:*}" n="${1##*:}"
  printf '%s' "$n" | grep -Eq '^[0-9]+$' || return 1
  [ -f "$APPDIR/$f" ] || return 1
  [ "$(awk 'END { print NR }' "$APPDIR/$f")" -ge "$n" ] && [ "$n" -ge 1 ]
}
cmd_score() {
  local items="$T/items" g="" gown="" f l n mark ev own pct ok tot r h
  need_cur sc; [ "$(st sc)" = "진행" ] || die 1 "[그래프 $APP] sc 가 진행 상태가 아닙니다($(st sc))."
  : > "$items"
  local srv=bf; has_server && srv=bb
  # 1. 필수 관문
  if ! run_tests; then g="승인 테스트 100% 통과 아님"; gown=bf
  elif ! lock_ok; then g="잠금 해시 다름"; gown=""
  elif ! secrets_ok; then g="비밀값 검사 걸림"; gown=$srv
  elif [ -f "$APPDIR/docs/redteam.md" ] && grep -Eq '^[[:space:]]*- \[뚫림\] \[심각\].*해결: *아직' "$APPDIR/docs/redteam.md"; then g="레드팀 심각 뚫림 남음"; gown=$srv
  elif [ -f "$APPDIR/.redteam-needed" ]; then g=".redteam-needed 남음"; gown=rt
  fi
  r="$(kget score.rounds)"; r=$(( ${r:-0} + 1 ))
  if [ -n "$g" ]; then
    kset score.rounds "$r"; kset score.last "관문 실패: $g"
    if [ -z "$gown" ]; then
      setst sc "사장보고"; set_wait sc "②" "필수 관문: $g — 승인 테스트는 사장 허락 없이 못 고침"; log_add gate sc "" "$g"; write_state
      die 4 "[그래프 $APP·sc] 필수 관문 실패: $g → 사장 보고(②)."
    fi
    write_state
    say "[그래프 $APP·sc] 필수 관문 실패: $g → 점수 계산 전에 $gown 로 자동으로 보냅니다."
    cmd_fail sc "필수 관문: $g" "$gown"; return
  fi
  # 2. 항목
  while IFS="$(printf '\t')" read -r n _ _ own; do
    l="$( [ -f "$APPDIR/docs/checklist.md" ] && grep -E "^\|[[:space:]]*$n[[:space:]]*\|" "$APPDIR/docs/checklist.md" | head -n1)"
    if [ -z "$l" ]; then echo "fail	$own	체크리스트 $n: 줄 없음" >> "$items"; continue; fi
    if printf '%s' "$l" | grep -q '해당 없음'; then continue; fi
    ev="$(printf '%s' "$l" | sed -n 's/.*근거:[[:space:]]*\([^ |]*\).*/\1/p')"
    if printf '%s' "$l" | grep -q '✓' && evid_ok "$ev"; then echo "ok	$own	체크리스트 $n" >> "$items"
    else echo "fail	$own	체크리스트 $n$(printf '%s' "$l" | grep -q '✓' && echo ' (근거 없음)')" >> "$items"; fi
  done < "$CT"
  for f in review.md review_codex.md review_result.md ui-check.md; do
    [ -f "$APPDIR/docs/$f" ] || continue
    grep -E '^[[:space:]]*- \[맞음\]' "$APPDIR/docs/$f" | while IFS= read -r l; do
      own="$(printf '%s' "$l" | sed -n 's/.*담당:[[:space:]]*\([a-z-]*\).*/\1/p')"; own="${own:-bf}"
      ev="$(printf '%s' "$l" | sed -n 's/.*해결:[[:space:]]*\([^ ]*\).*/\1/p')"
      if evid_ok "$ev"; then echo "ok	$own	$f: $(printf '%s' "$l" | cut -c1-60)"; else echo "fail	$own	$f: $(printf '%s' "$l" | cut -c1-60)"; fi
    done >> "$items"
  done
  if [ "$(st dv)" != "건너뜀" ]; then
    perf_check | while read -r mark k own rest; do printf '%s\t%s\t성능 %s %s\n' "$mark" "$own" "$k" "$rest"; done >> "$items"
  fi
  if [ -f "$APPDIR/docs/requirements.md" ]; then
    awk '/^## 꼭 되어야 할 기능/ { f=1; next } /^## / { f=0 } f && /^[[:space:]]*- F[0-9]+/ { sub(/^[[:space:]]*- /, ""); print }' "$APPDIR/docs/requirements.md" |
    while read -r fid rest; do
      f="$( [ -f "$APPDIR/docs/tests.md" ] && grep -E "^[[:space:]]*- $fid[[:space:]]" "$APPDIR/docs/tests.md" | head -n1 | sed -n 's/.*(\([^)]*\)).*/\1/p')"
      if [ -n "$f" ] && [ -f "$APPDIR/$f" ] && bash "$HOOKS/check-approved.sh" listed "$APPDIR" "$APPDIR/$f" </dev/null >/dev/null 2>&1; then
        echo "ok	bf	기능 $fid $rest"; else echo "fail	bf	기능 $fid $rest (승인 테스트로 확인 안 됨)"; fi
    done >> "$items"
  fi
  ok="$(grep -c '^ok' "$items")"; tot="$(grep -c '' "$items")"
  [ "$tot" -gt 0 ] || tot=1
  pct=$(( ok * 100 / tot ))
  h="$(kget score.history)"; h="${h:+$h,}$pct"
  kset score.rounds "$r"; kset score.history "$h"; kset score.last "$pct% ($ok/$tot)"
  mkdir -p "$APPDIR/docs"
  { echo "# 완성도 점수 — $r바퀴째 $pct% ($ok/$tot) $(NOW)"; echo; echo "| 결과 | 담당 | 항목 |"; echo "|---|---|---|"
    awk -F'\t' '{ printf "| %s | %s | %s |\n", ($1=="ok"?"✓":"✗"), $2, $3 }' "$items"; } > "$APPDIR/docs/score.md"
  log_add score sc "" "$pct% ($ok/$tot)"
  if [ $((ok * 100)) -ge $((90 * tot)) ]; then
    advance sc ""; write_state
    say "[그래프 $APP·sc] 완성도 $pct% ($ok/$tot) ≥ 90% → ok-qa(★ QA 보고). docs/score.md의 ✓/✗, 남은 항목과 추천, docs/ask-later.md를 한 번에 보고하세요."
    return 0
  fi
  # 브레이크: 5바퀴 초과, 2바퀴 연속 정체
  local stall; stall="$(printf '%s' "$h" | awk -F, 'NF>=3 && $NF<=$(NF-1) && $(NF-1)<=$(NF-2) { print 1 }')"
  if [ "$r" -gt 5 ] || [ -n "$stall" ]; then
    setst sc "사장보고"; set_wait sc "②" "완성도 $pct% — $([ -n "$stall" ] && echo '2바퀴 연속 정체' || echo '5바퀴 초과')"
    log_add brake sc "" "$pct%"; write_state
    die 4 "[그래프 $APP·sc] 완성도 $pct% — $([ -n "$stall" ] && echo '2바퀴 연속 점수가 오르지 않음' || echo '점수 바퀴 5번 초과') → 사장 보고(②). docs/score.md의 못 넘은 항목·이유·추천으로 보고하세요."
  fi
  # 가장 많이 깎은 담당 노드로
  own="$(awk -F'\t' '$1=="fail" && $2!="-" { c[$2]++ } END { for (k in c) print c[k], k }' "$items" | sort -k1,1nr -k2 | while read -r cnt o; do
    case "$o" in bb|bf|ui|rt) [ "$(st "$o")" = "건너뜀" ] || { echo "$o"; break; } ;; esac; done)"
  [ -n "$own" ] || own=bf
  write_state
  say "[그래프 $APP·sc] 완성도 $pct% ($ok/$tot) < 90% → 가장 많이 깎은 $own 로 자동으로 보냅니다(docs/score.md)."
  cmd_fail sc "완성도 $pct% — $own 담당 항목 미통과" "$own"
}

cmd_current() {
  if [ "$1" = "--status" ]; then for c in $(cur | tr ',' ' '); do printf '%s:%s\n' "$c" "$(st "$c")"; done
  else cur; echo; fi
}
cmd_get() {
  case "$1" in
    approval) has_approval "$2" ;;
    status) st "$2"; echo ;;
    locked) locked_before ;;
    *) die 1 "get approval <노드> | status <노드> | locked" ;;
  esac
}

status_short() {
  local c id parts="" w
  c="$(cur)"
  for id in $(printf '%s' "$c" | tr ',' ' '); do
    parts="${parts:+$parts · }$id $(nname "$id")[$(st "$id")] → 다음 $(nf "$id" 9) · 통과 조건: $(nf "$id" 7)"
  done
  w="$(kget wait.kind)"
  [ -z "$c" ] && [ "$(st done)" = "통과" ] && parts="끝(완료)"
  printf '[그래프 %s] %s%s\n' "$APP" "${parts:-현재 노드 없음}" "${w:+ · 멈춤 $w: $(kget wait.line)}"
}
cmd_status() {
  [ "$1" = "--short" ] && { status_short; return; }
  status_short
  local id s
  say "노드별:"
  for id in $(ids); do
    s="$(st "$id")"
    printf '  %-6s %-24s %s%s\n' "$id" "$(nname "$id")" "$s" "$( [ "$(nnum "$id" retries)" != 0 ] && echo " (되돌아옴 $(nnum "$id" retries))")"
  done
  [ -n "$(kget resume)" ] && say "고친 뒤 갈 곳: $(kget resume)"
  [ -n "$(kget queue)" ] && say "고칠 차례 대기: $(kget queue)"
  [ -n "$(kget lf.from)" ] && say "마지막 실패: $(kget lf.from) → $(kget lf.to) ($(kget lf.reason), $(kget lf.at))"
  [ -n "$(kget score.last)" ] && say "완성도: $(kget score.last) (바퀴 $(kget score.rounds), 기록 $(kget score.history))"
  say "승인 기록: $(grep -c '' "$AP")건"
}

cmd_init() {
  [ -e "$STATE" ] && die 1 "[그래프 $APP] state.json이 이미 있습니다. 이어 하기: graph.sh status $APPDIR"
  mkdir -p "$APPDIR"
  printf 'version\t1\napp\t%s\n' "$APP" > "$KV"
  log_add init "$APP" "" "새 앱"
  enter req
  write_state; status_short
}
cmd_migrate() {
  [ -e "$STATE" ] && die 1 "[그래프 $APP] state.json이 이미 있습니다."
  [ -d "$APPDIR" ] || die 1 "$APPDIR 폴더가 없습니다."
  local n id o
  n="$( [ -f "$APPDIR/HANDOFF.md" ] && grep -m1 '^현재 단계:' "$APPDIR/HANDOFF.md" | grep -Eo '[1-6]' | head -n1)"
  printf 'version\t1\napp\t%s\n' "$APP" > "$KV"
  for id in $(ids); do
    o="$(nf "$id" 15)"
    if [ -z "$n" ]; then setst "$id" "확인필요"
    elif [ "$o" -lt "$n" ]; then setst "$id" "통과"; [ "$(nf "$id" 3)" = "사람" ] && printf '%s\t%s\t%s\n' "$id" "$(NOW)" "이전 방식" >> "$AP"
    elif [ "$o" -eq "$n" ]; then setst "$id" "확인필요"
    else setst "$id" "대기"; fi
  done
  [ "$(st done)" = "확인필요" ] && setst done 대기
  log_add migrate "$APP" "" "HANDOFF 현재 단계: ${n:-못 읽음}"
  write_state
  say "[그래프 $APP] 옮김(HANDOFF 현재 단계: ${n:-못 읽음}). 끝난 단계 = 통과(승인 '이전 방식'), 애매한 노드 = 확인 필요:"
  for id in $(ids); do [ "$(st "$id")" = "확인필요" ] && say "  - $id $(nname "$id")"; done
  say "추측하지 말고 사장에게 보기 + 추천으로 물은 뒤 graph.sh confirm $APPDIR <노드> 통과|대기"
}
cmd_confirm() {
  local id="$1" v="$2" n
  is_node "$id" || die 1 "graph.md에 없는 노드: $id"
  [ "$(st "$id")" = "확인필요" ] || die 1 "[그래프 $APP] $id 는 확인 필요 상태가 아닙니다."
  case "$v" in 통과|대기) ;; *) die 1 "통과 또는 대기" ;; esac
  setst "$id" "$v"; log_add confirm "$id" "" "$v"
  local left=""; for n in $(ids); do [ "$(st "$n")" = "확인필요" ] && left="$left $n"; done
  if [ -z "$left" ] && [ -z "$(cur)" ]; then
    for n in $(ids); do [ "$(st "$n")" = "대기" ] && { enter "$n"; break; }; done
  fi
  write_state; say "[그래프 $APP] $id = $v${left:+ (남은 확인 필요:$left)}"; [ -z "$left" ] && status_short
}

cmd_lint() {
  local errs="" id x t f
  add() { errs="$errs
- $1"; }
  [ -z "$(ids | sort | uniq -d)" ] || add "id 중복: $(ids | sort | uniq -d | paste -sd, -)"
  while IFS="$(printf '\t')" read -r id _ kind _ _ out _ chk nx rw jn fs mx sk old; do
    case "$kind" in AI|프로그램|외부AI|사람|AI+프로그램|끝) ;; *) add "$id: 모르는 종류 $kind" ;; esac
    case "$chk" in -|lock|backend|tests|perf|redteam|secrets|score) ;; *) add "$id: 모르는 검사 $chk" ;; esac
    for x in $(opts "$nx") $(opts "$rw") $(opts "$jn"); do [ "$x" = "-" ] || is_node "$x" || add "$id: 없는 노드로 가는 엣지 $x"; done
    t="$(awk -F'\t' -v f="$id" '$1==f { print $2 }' "$FP" | sort -u | paste -sd, -)"
    f="$(opts "$fs" | tr ' ' '\n' | grep -v '^-$' | sort -u | paste -sd, -)"
    [ "$t" = "$f" ] || add "$id: '실패 시' 칸($f)과 실패 엣지 표($t)가 다름"
    case "$nx" in *+*)
      local outs; outs="$(for x in $(opts "$nx"); do nf "$x" 6 | tr ',' '\n' | sed 's/^ *//; s/ *$//'; done | grep -v '^-$' | sort | uniq -d)"
      [ -z "$outs" ] || add "$id: 동시 노드($nx)가 같은 파일을 씀: $(printf '%s' "$outs" | paste -sd, -)" ;;
    esac
    printf '%s' "$mx" | grep -Eq '^([0-9]+|-)$' || add "$id: 최대 칸은 숫자 또는 -"
    printf '%s' "$old" | grep -Eq '^[1-6]$' || add "$id: 옛 단계는 1~6"
  done < "$NT"
  while IFS="$(printf '\t')" read -r f t _ _ _; do
    is_node "$f" || add "실패 엣지 출발 없음: $f"; is_node "$t" || add "실패 엣지 도착 없음: $t"
  done < "$FP"
  # req 에서 다음·다시 엣지로 모두 닿는지
  local seen=" req " q="req" c
  while [ -n "$q" ]; do
    c="${q%% *}"; q="${q#"$c"}"; q="${q# }"
    for x in $(opts "$(nf "$c" 9)") $(opts "$(nf "$c" 10)"); do
      [ "$x" = "-" ] && continue
      case "$seen" in *" $x "*) ;; *) seen="$seen$x "; q="${q:+$q }$x" ;; esac
    done
  done
  for id in $(ids); do case "$seen" in *" $id "*) ;; *) add "req에서 닿지 않는 노드: $id" ;; esac; done
  [ "$(grep -c '' "$CT")" -eq 20 ] || add "체크리스트가 20줄이 아님($(grep -c '' "$CT"))"
  while IFS="$(printf '\t')" read -r n _ _ own; do [ "$own" = "-" ] || is_node "$own" || add "체크리스트 $n 담당 없음: $own"; done < "$CT"
  grep -q '<!-- relock: ' "$GRAPH" || add "다시 잠그기 안내 줄(relock)이 없음"
  if [ -n "$errs" ]; then die 1 "graph.md 점검 실패:$errs"; fi
  say "graph.md 점검 통과: 노드 $(grep -c '' "$NT")개, 실패 엣지 $(grep -c '' "$FP")개, 체크리스트 $(grep -c '' "$CT")개"
}

usage() {
  cat <<'U'
사용: bash .claude/skills/build-app/graph.sh <명령> apps/<앱> [인자]
  status [--short]               현재 노드·상태·다음·통과 조건·멈춤 이유
  pass <노드> [다음]             통과(⚙️ 검사는 여기서 직접) → 다음 노드
  fail <노드> "<이유>" [보낼 곳]  실패 엣지 표에 있는 곳으로만 (여럿: bb,bf)
  approve <★노드> "<사장 답>"     ★ 승인 기록(답 원문 짧게)
  budget <예상 토큰|0>           탐색·사용성 예상(0 = 건너뛰기) — ok-ip에서
  usage <실제 토큰>              탐색·사용성 사용량(예상 2배 초과면 ④)
  skip <노드[,노드]> "<이유>"     건너뛰기 칸이 있는 노드만
  wait <노드> ["<한 줄>"]        ⑤ 사장이 실행할 한 줄을 남기고 대기
  stuck <노드> 도구|보고 "<내용>"  ③ 도구 없음 / ② 사장 보고
  resume <노드>                  멈춤(②③④⑤)을 풀고 다시 진행
  loop                           (Stop 훅) 구현 노드 통과 검사·회차 세기
  score                          (sc) 필수 관문 + 완성도 점수
  init | migrate | confirm <노드> 통과|대기 | current [--status] | get … | lint
U
}

# ---------------- 실행 ----------------
cmd="$1"; shift 2>/dev/null
case "$cmd" in
  lint) cmd_lint; exit ;;
  ""|-h|--help|help) usage; exit 0 ;;
esac
set_app "$1"; shift 2>/dev/null
case "$cmd" in
  init) cmd_init ;;
  migrate) cmd_migrate ;;
  *) parse_state
     case "$cmd" in
       status) cmd_status "$@" ;;
       pass) cmd_pass "$@" ;;
       fail) cmd_fail "$@" ;;
       approve) cmd_approve "$@" ;;
       wait) cmd_wait "$@" ;;
       stuck) cmd_stuck "$@" ;;
       resume) cmd_resume "$@" ;;
       skip) cmd_skip "$@" ;;
       budget) cmd_budget "$@" ;;
       usage) cmd_usage "$@" ;;
       loop) cmd_loop ;;
       score) cmd_score ;;
       current) cmd_current "$@" ;;
       get) cmd_get "$@" ;;
       confirm) cmd_confirm "$@" ;;
       *) usage; exit 1 ;;
     esac ;;
esac

#!/usr/bin/env bash
# UserPromptSubmit: 사장 메시지가 앱 작업이면 그래프의 현재 노드 → 다음 · 통과 조건을 한 줄씩 Claude에게 넣어 준다.
# 잡담이면 아무것도 넣지 않는다. 메시지를 막지 않는다(항상 exit 0 — exit 2 는 메시지를 막으므로 쓰지 않음).
# 앱 작업 턴이면 .git/graph-turn 표시를 남긴다(커밋 안 됨). graph-stop.sh 가 이 표시를 보고 자동 진행을 챙긴다.
# 판별은 글자 검사라 틀릴 수 있다(남은 위험). 근거: https://code.claude.com/docs/en/hooks#userpromptsubmit-input

input="$(cat)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0
gd="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
G="$(cd "$(dirname "$0")" && pwd)/../skills/build-app/graph.sh"
rm -f "$gd/graph-turn"

# JSON 의 "prompt" 값 (이스케이프 풀기)
prompt="$(printf '%s' "$input" | awk 'BEGIN{RS="\001"} {
  s=$0; p=index(s, "\"prompt\""); if (!p) exit
  s=substr(s, p+8); if (!match(s, /^[ \t\r\n]*:[ \t\r\n]*"/)) exit
  s=substr(s, RLENGTH+1); n=length(s); out=""
  for (i=1; i<=n; i++) { ch=substr(s,i,1)
    if (ch=="\\") { i++; e=substr(s,i,1); if (e=="n") out=out " "; else if (e=="t") out=out " "; else if (e=="u") i+=4; else out=out e; continue }
    if (ch=="\"") break; out=out ch }
  printf "%s", out }')"
[ -z "$prompt" ] && exit 0

lines=""; names=""; waiting=""
for s in apps/*/state.json; do
  [ -f "$s" ] || continue
  app="$(dirname "$s")"
  st="$(bash "$G" current "$app" --status </dev/null 2>/dev/null)"; rc=$?
  if [ $rc -eq 3 ]; then lines="$lines
[그래프 $(basename "$app")] state.json 이 깨졌습니다 — 추측해서 고치지 말고 사장에게 알리세요."; names="$names|$(basename "$app")"; continue; fi
  [ $rc -eq 0 ] && [ -n "$st" ] || continue
  names="$names|$(basename "$app")"
  printf '%s\n' "$st" | grep -q ':사장대기$' && waiting=1
  lines="$lines
$(bash "$G" status "$app" --short </dev/null 2>/dev/null)"
done

kw='앱|만들|기능|추가|이어|계속|고쳐|수정|build-app|해결됐어요|아직이에요|승인|진행|테스트|화면|버그|배포|올려|설계|기획|디자인'
app_work=""
printf '%s' "$prompt" | grep -Eq "$kw" && app_work=1
[ -n "$names" ] && printf '%s' "$prompt" | grep -Eq "(${names#|})" && app_work=1
# ★·사장 대기 중의 짧은 답(예: "OK", "2번", "좋아요")도 앱 작업
[ -n "$waiting" ] && [ "$(printf '%s' "$prompt" | LC_ALL=C awk '{ n+=length($0) } END { print n+0 }')" -le 60 ] && app_work=1
[ -z "$app_work" ] && exit 0

echo "turn" > "$gd/graph-turn"
if [ -z "$lines" ]; then
  echo "[그래프] 앱 작업이면 /build-app — 새 앱은 graph.sh init apps/<이름> 후 req 노드부터, 그래프 이전 앱은 graph.sh migrate apps/<앱>. 흐름: .claude/skills/build-app/graph.md"
else
  echo "[그래프] 앱 작업 — state.json의 현재 노드부터 자동으로 이어 가세요(멈춤은 graph.md의 다섯 가지뿐):${lines}"
fi
exit 0

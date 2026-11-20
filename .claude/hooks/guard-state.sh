#!/usr/bin/env bash
# apps/<앱>/state.json 은 graph.sh 만 쓴다. Edit/Write/MultiEdit 로 직접 고치면 막는다. (PreToolUse: Edit|Write|MultiEdit)
# Bash 로 직접 쓰는 것(echo > 등)은 글자 검사로 다 못 막는다 → graph.sh 형식 검사 + log + qa-reviewer 대조로 잡는다.
# 종료 코드 2 = 막기, 0 = 통과. jq 없이 동작한다.

input="$(cat)"
file="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's/\\\\/\//g; s/\\/\//g')"
[ -z "$file" ] && exit 0
if printf '%s' "$file" | grep -Eq '(^|/)apps/[^/]+/state\.json$'; then
  echo "[그래프] state.json 은 직접 고치지 않습니다. graph.sh 로만 바꾸세요(pass / fail / approve / skip / stuck / resume …).
깨졌다면 추측해서 고치지 말고 사장에게 알리세요." >&2
  exit 2
fi
exit 0

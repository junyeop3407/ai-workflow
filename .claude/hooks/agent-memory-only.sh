#!/usr/bin/env bash
# 검수 에이전트(qa-reviewer, red-team)는 코드를 고치지 않는다. 메모리(memory: project)를 쓰려면
# Write·Edit가 켜져야 해서, 그 대신 이 훅이 "자기 메모리 폴더 밖"을 막는다. (PreToolUse: Edit|Write|MultiEdit|NotebookEdit)
#   agent-memory-only.sh <에이전트>  : 에이전트 파일(frontmatter hooks:)에서 — 그 에이전트가 돌 때만 실행됨
#   agent-memory-only.sh             : settings.json에서 — 입력의 agent_type이 qa-reviewer·red-team일 때만 검사
#   (폴더를 신뢰하기 전에는 frontmatter 훅이 건너뛰어질 수 있어 두 겹으로 건다)
# 허용: .claude/agent-memory/<에이전트>/ 아래, ".." 없는 경로. 그 밖은 exit 2. jq 없이 동작한다.

input="$(cat)"
agent="$1"
if [ -z "$agent" ]; then
  agent="$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
case "$agent" in
  qa-reviewer|red-team) ;;
  *) exit 0 ;;
esac

file="$(printf '%s' "$input" | sed -n 's/.*"\(file_path\|notebook_path\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -n1 | sed 's/\\\\/\//g; s/\\/\//g')"

case "$file" in
  *..*) ;;
  .claude/agent-memory/"$agent"/*|*/.claude/agent-memory/"$agent"/*) exit 0 ;;
esac

echo "훅이 막았습니다: $agent 에이전트는 파일을 고치지 않습니다. 쓸 수 있는 곳은 .claude/agent-memory/$agent/ (메모리)뿐입니다. (시도한 파일: ${file:-알 수 없음})
찾은 문제는 고치지 말고 답에 적어 메인 대화에 넘기세요." >&2
exit 2

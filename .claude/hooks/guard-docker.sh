#!/usr/bin/env bash
# Claude·에이전트가 docker를 직접 부르지 못하게 막는다 (PreToolUse: Bash|PowerShell). docs/docker-review.md 4절.
# Docker 일은 `bash .claude/hooks/dock.sh …`(정책 검사 뒤 실행)로만. AI는 요청하고, dock.sh가 검증하고 실행한다.
# 막는 것: 명령 자리에 오는 docker / docker-compose / podman / nerdctl (경로·.exe·sudo·env·xargs 등 앞붙이 포함),
#          Docker 엔진 통로(docker.sock, Windows docker_engine 파이프)를 가리키는 명령.
# 남은 위험: 스크립트 파일 안에서 docker를 부르는 것은 명령 글자에 안 보인다 → dock.sh 밖 스크립트에 docker를 쓰지 않는다(규칙),
#           compose 파일은 dock.sh up 이 검사.

input="$(cat)"
cmd="$(printf '%s' "$input" | tr '\n' ' ' | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | sed 's/\\"/"/g; s/\\\\/\\/g; s/\\n/ ; /g')"
[ -z "$cmd" ] && exit 0

block() {
  echo "훅이 막았습니다: $1
Docker는 'bash .claude/hooks/dock.sh <check|pin|run|up|down|ps|clean> …'로만 씁니다(정책 검사 뒤 실행). 필요한 동작이 dock.sh에 없으면 사장에게 알리세요." >&2
  exit 2
}

# dock.sh 부르기는 통과 대상이므로 그 글자를 지운 뒤 본다
rest="$(printf '%s' "$cmd" | sed 's#[^[:space:];&|]*\.claude/hooks/dock\.sh#DOCKSH#g')"
low="$(printf '%s' "$rest" | tr 'A-Z' 'a-z')"
# 따옴표 안 글자(검색어·커밋 메시지)는 실행되지 않으므로 빼고 본다 — 단, 따옴표 안 글자를 실행하는 꼴(bash -c·sh -c·eval·
# xargs·pwsh -command·cmd /c·source·ssh·wsl)이 있으면 따옴표 안까지 그대로 본다(모르면 막기)
if ! printf '%s' "$low" | grep -Eq '(^|[[:space:];&|(`])(eval|bash|sh|zsh|dash|ksh|pwsh|powershell|cmd|cmd\.exe|xargs|parallel|source|ssh|wsl|watch|env)([[:space:]]|$)|(^|[[:space:]])(-c|-command|/c)([[:space:]]|$)|\$\(|`'; then
  low="$(printf '%s' "$low" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g")"
fi

printf '%s' "$low" | grep -Eq 'docker\.sock|docker_engine|dockerd([[:space:]]|$)|com\.docker\.' \
  && block "Docker 엔진 통로(docker.sock·docker_engine)·엔진 자체를 직접 건드리는 명령입니다."

# 명령 자리: 줄 맨 앞, ; & | ( ` $( 뒤, 그리고 sudo/env/command/exec/nohup/time/xargs/watch/wsl/& 같은 앞붙이 뒤
pre='(^|[;&|(`]|\$\()[[:space:]]*((sudo|env|command|exec|nohup|time|xargs|watch|wsl|nice|timeout|start|cmd|cmd\.exe|powershell|pwsh|bash|sh|zsh|dash|ksh|eval|source|parallel|ssh)([[:space:]]+-[^[:space:]]+)*([[:space:]]+[a-z_][a-z0-9_]*=[^[:space:]]*)*[[:space:]]+|/c[[:space:]]+|&[[:space:]]+)*'
tool='("|'"'"')?([^[:space:];&|"'"'"']*[/\\])?(docker|docker-compose|podman|nerdctl)(\.exe)?("|'"'"')?([[:space:]]|$)'
printf '%s' "$low" | grep -Eq "$pre$tool" && block "docker(또는 podman·nerdctl)를 직접 부르는 명령입니다."
# 변수에 담아 부르기(d=docker; \$d …)·문자열로 만들어 부르기도 막음
printf '%s' "$low" | grep -Eq '=[[:space:]]*("|'"'"')?[^[:space:];&|]*(docker|podman|nerdctl)(\.exe)?("|'"'"')?([[:space:];]|$)' \
  && block "docker를 변수에 담아 부르는 명령입니다."
exit 0

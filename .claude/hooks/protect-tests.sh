#!/usr/bin/env bash
# "승인된 테스트는 사장 허락 없이 고치거나 지우지 않는다"를 시스템으로 지킨다.
# (PreToolUse: Edit|Write|MultiEdit 와 Bash|PowerShell 둘 다에 등록)
#
# 승인 목록 = apps/<앱>/tests/.approved ("<sha256>  <저장소 기준 경로>" 한 줄씩).
#   사장이 3단계에서 직접 `! bash .claude/hooks/approve-tests.sh apps/<앱>` 로 만든다.
#   커밋 여부와 상관없이 이 목록에 있으면 승인된 테스트다.
#
# Edit/Write/MultiEdit:
#   - .approved 목록에 있는 파일, .approved 자체를 고치면 → 사장 확인 창(ask)
#   - 실행 파일(.sh .ps1 .bat .cmd .py .js .ts .mjs)에 approve-tests·.approved 글자를 쓰면 → 막음(exit 2)
#     (승인 스크립트를 흉내 낸 새 스크립트로 다시 잠그는 우회 차단. .md 문서와 .claude/hooks/ 는 제외)
# Bash/PowerShell:
#   - 명령에 approve-tests·.approved 글자가 있으면 → 막음(exit 2). 승인은 사장만 한다.
#     단, 읽기만 하는 명령(git log/diff/show/status, cat, head, tail, grep, sha256sum, 리디렉션·tee 없음)은 통과.
# 글자 검사라 완벽하지 않다(문자열을 쪼개 만드는 우회 등). 그래서 check-approved.sh가 커밋 직전·Stop에서
# 해시를 다시 비교하고, 5단계 qa-reviewer가 .approved 변경 기록을 본다.
# jq 없이 동작한다.

input="$(cat)"
tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

block() {
  echo "훅이 막았습니다: $1
테스트 승인(.approved 기록)은 사장만 합니다. Claude는 실행하지 말고, 사장에게 이 한 줄을 부탁하세요:
  ! bash .claude/hooks/approve-tests.sh apps/<앱>
(우회하지 마세요. CLAUDE.md '절대 하지 않을 것')" >&2
  exit 2
}

# ---- Bash / PowerShell ----
if [ "$tool" = "Bash" ] || [ "$tool" = "PowerShell" ]; then
  cmd="$(printf '%s' "$input" | tr '\n' ' ' | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' \
    | sed 's/"[[:space:]]*,[[:space:]]*"[a-z_]*"[[:space:]]*:.*//; s/"[[:space:]]*}.*//' | sed 's/\\"/"/g; s/\\\\/\\/g')"
  printf '%s' "$cmd" | grep -Eq 'approve-tests|\.approved' || exit 0

  # 읽기만 하는 명령인지
  readonly_ok() {
    local c="$1"
    # 명령 치환·tee·파일로 내보내는 옵션은 읽기가 아님
    printf '%s' "$c" | grep -Eq '\$\(|`|(^|[^A-Za-z])tee([^A-Za-z]|$)|--output' && return 1
    # 2>&1, >/dev/null 은 무해하니 지우고, 그래도 > 가 남으면 쓰기
    c="$(printf '%s' "$c" | sed -E 's/[0-9]*>&[0-9]+//g; s#[0-9]*>>?[[:space:]]*/dev/null##g')"
    printf '%s' "$c" | grep -q '>' && return 1
    # 줄바꿈(JSON의 \n)·; · && · || · | · & 로 나눈 조각이 모두 허용된 읽기 명령이어야 한다
    local segs
    segs="$(printf '%s' "$c" | sed -E 's/\\n/\n/g; s/(\|\||&&|;|\||&)/\n/g')"
    while IFS= read -r seg; do
      seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$seg" ] && continue
      printf '%s' "$seg" | grep -Eq '^(git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(log|diff|show|status)|cat|head|tail|grep|sha256sum)([[:space:]]|$)' || return 1
    done <<< "$segs"
    return 0
  }
  readonly_ok "$cmd" && exit 0
  block "명령에 approve-tests 또는 .approved 가 들어 있습니다(읽기 전용 명령이 아님): $cmd"
fi

# ---- Edit / Write / MultiEdit ----
file="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's/\\\\/\//g; s/\\/\//g')"
[ -z "$file" ] && exit 0

# 1. 실행 파일에 승인 글자를 쓰면 막는다 (.claude/hooks/ 안의 훅·시험 스크립트는 제외)
case "$file" in
  */.claude/hooks/*|.claude/hooks/*) ;;
  *.sh|*.ps1|*.bat|*.cmd|*.py|*.js|*.ts|*.mjs)
    printf '%s' "$input" | grep -Eq 'approve-tests|\.approved' \
      && block "실행 파일($file)에 approve-tests 또는 .approved 를 쓰려 합니다." ;;
esac

# 2. apps/<앱>/tests/ 아래만 승인 목록과 비교
rel="$(printf '%s' "$file" | sed -n 's#^\(.*/\)\{0,1\}\(apps/[^/]*/tests/.*\)$#\2#p')"
[ -z "$rel" ] && exit 0
app_tests="$(printf '%s' "$rel" | sed -n 's#^\(apps/[^/]*/tests\)/.*#\1#p')"

ask() {
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$1"}}
JSON
  exit 0
}

case "$rel" in
  */.approved)
    ask "승인 목록($rel)을 직접 고치려 합니다. 승인은 사장이 '! bash .claude/hooks/approve-tests.sh apps/<앱>'로만 합니다. 거절을 권합니다." ;;
esac

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
list="$root/$app_tests/.approved"
[ -f "$list" ] || exit 0
# 목록의 경로 칸(두 번째 칸부터)이 정확히 같은 줄이 있으면 승인된 테스트
if sed -n 's/^[0-9a-f]\{64\}  //p' "$list" | grep -qxF "$rel"; then
  ask "승인된 테스트($rel)를 고치려 합니다. 사장 허락 없이는 고치지 않는 규칙입니다. 검사 내용·숫자는 그대로이고 찾는 위치만 바뀌는지 확인한 뒤 허용해 주세요. 허용했다면 고친 뒤 사장이 다시 잠가야 합니다(! bash .claude/hooks/approve-tests.sh apps/<앱>)."
fi
exit 0

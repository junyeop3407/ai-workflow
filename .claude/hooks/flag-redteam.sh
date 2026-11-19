#!/usr/bin/env bash
# "결제·로그인·회원정보를 고쳤으면 레드팀을 다시 돌린다"를 시스템으로 지킨다.
#   flag-redteam.sh         : PostToolUse(Edit|Write|MultiEdit) — 고친 파일 하나를 검사
#   flag-redteam.sh commit  : PreToolUse(Bash|PowerShell) git commit 직전 — 커밋될 파일 이름을 모두 검사
#                             (sed·cp·mv 같은 Bash로 고친 것도 여기서 잡는다. 커밋은 막지 않는다)
# apps/<앱>/ 안에서 보안에 민감한 파일(로그인·토큰·결제·쿠폰·회원·관리자 등)이 바뀌면
# apps/<앱>/.redteam-needed 표시를 만들고, 처음 만들 때 한 번만 Claude에게 알린다.
# 표시는 레드팀을 다시 돌려 뚫린 것을 다 고친 뒤 지운다(/build-app "레드팀 공격").
# 테스트·문서 파일은 무시한다. jq 없이 동작한다.

mode="$1"
input="$(cat)"

# 저장소 기준 경로(apps/<앱>/...)가 민감한 파일이면 0
is_sensitive() {
  local rel="$1" low
  case "$rel" in
    */tests/*|*/test/*|*/docs/*|*.md|*/.redteam-needed) return 1 ;;
    *.css|*.scss|*.sass|*.less|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.woff|*.woff2|*.ttf|*.lock) return 1 ;;
  esac
  # 경로 조각(폴더·파일 이름)이 아래 단어로 "시작"할 때만 (대소문자 무시)
  # 예) AuthController.java, jwt/, PaymentService.java, admin/ → 해당 / border.css, endpoint.ts, UserCard.tsx → 아님
  low="$(printf '%s' "$rel" | tr 'A-Z' 'a-z')"
  printf '%s' "$low" | grep -Eq '(^|[/._-])(auth|login|logout|signin|signup|session|token|jwt|password|passwd|oauth|security|payment|pay[/._-]|checkout|order|price|coupon|point|wallet|refund|billing|member|account|admin|role|permission|upload|webhook|user(s)?(service|controller|repository|repo|api|route|handler|[/._-]))'
}

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# 민감한 파일 목록(저장소 기준 경로, 줄 단위)을 받아 앱마다 표시를 만든다. 새로 만든 표시가 있으면 알린다.
flag_all() {
  local event="$1" list="$2" rel app flag msg=""
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    app="$(printf '%s' "$rel" | sed -n 's#^apps/\([^/]*\)/.*$#\1#p')"
    [ -z "$app" ] && continue
    is_sensitive "$rel" || continue
    flag="$root/apps/$app/.redteam-needed"
    [ -f "$flag" ] && continue   # 이미 표시가 있으면 조용히 (같은 알림 반복 안 함)
    printf '%s\n' "$rel" > "$flag" 2>/dev/null || continue
    msg="$msg 보안에 민감한 파일($rel)이 바뀌었습니다. apps/$app/.redteam-needed 표시를 만들었습니다."
  done <<< "$list"
  [ -z "$msg" ] && return 0
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"$event","additionalContext":"$msg 이 앱은 QA 보고·배포·커밋 마무리 전에 red-team 에이전트를 다시 돌려야 합니다(/build-app '레드팀 공격'). 다 고친 뒤 표시를 지우세요."}}
JSON
}

if [ "$mode" = "commit" ]; then
  cmd="$(printf '%s' "$input" | tr '\n' ' ' | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' \
    | sed 's/"[[:space:]]*,[[:space:]]*"[a-z_]*"[[:space:]]*:.*//; s/"[[:space:]]*}.*//' | sed 's/\\"/"/g; s/\\\\/\\/g')"
  printf '%s' "$cmd" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit\b' || exit 0
  cd "$root" || exit 0
  # 커밋될 파일: 스테이지된 것 + (같은 명령에 git add / commit -a 가 있으면) 아직 안 올린 변경까지 (guard-git과 같은 방식)
  g() { git -c core.quotePath=false "$@"; }
  files="$(g diff --cached --name-only --diff-filter=ACMR -- apps)"
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+add\b|commit[^;&|]*[[:space:]]-[a-zA-Z]*a'; then
    files="$files
$(g diff --name-only --diff-filter=ACMR -- apps)
$(g ls-files --others --exclude-standard -- apps)"
  fi
  files="$(printf '%s\n' "$files" | sed '/^$/d; s/^"//; s/"$//' | sort -u)"
  flag_all PreToolUse "$files"
  exit 0
fi

# PostToolUse: 고친 파일 하나
file="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's/\\\\/\//g; s/\\/\//g')"
[ -z "$file" ] && exit 0
rel="$(printf '%s' "$file" | sed -n 's#^\(.*/\)\{0,1\}\(apps/[^/]*/.*\)$#\2#p')"
[ -z "$rel" ] && exit 0
flag_all PostToolUse "$rel"
exit 0

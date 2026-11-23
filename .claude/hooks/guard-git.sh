#!/usr/bin/env bash
# CLAUDE.md "절대 하지 않을 것"을 부탁이 아니라 시스템으로 막는다. (PreToolUse: Bash|PowerShell)
#   1. 강제 푸시, 커밋 기록 고쳐 쓰기, 저장소 삭제 → 항상 막음 (꼭 필요하면 사장이 직접 `!`로 실행)
#   2. git commit 직전: 커밋될 파일에 .env·키 파일·node_modules·빌드 결과물,
#      실제 업무 데이터 파일(엑셀·CSV 등, tests/fixtures/ 밖)·samples/ 폴더, 비밀값 패턴,
#      특정 컴퓨터 전용 경로(C:\Users\..., /Users/<이름>/, /home/<이름>/)가 있으면 막음
# jq 없이 동작한다 (Windows Git Bash에는 jq가 없는 경우가 많다).
# 종료 코드 2 = 막기 (stderr 내용이 Claude에게 전달된다), 0 = 통과.
#   guard-git.sh scan apps/<앱> : (graph.sh, 공개 여부 묻기 전) 앱의 지금 파일 전체(추적 중 + 새 파일)를
#                                 아래와 같은 비밀값 패턴·올리면 안 되는 파일로 검사. 걸리면 1 + 목록, 아니면 0.

# 비밀값 패턴 (커밋 검사와 scan이 같이 쓴다). 입력: "파일: 줄" 들
secret_grep() {
  grep -E \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'AIza[0-9A-Za-z_-]{35}' \
  -e '(sk|rk)-(live|proj|ant)?-?[A-Za-z0-9_-]{20,}' \
  -e 'gh[pousr]_[A-Za-z0-9]{36}' \
  -e 'xox[abpr]-[A-Za-z0-9-]{10,}' \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
  -e '(password|passwd|secret|api_?key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'$<{]{8,}["'"'"']'
}

if [ "$1" = "scan" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
  cd "$root" || exit 1
  app="${2%/}"
  [ -d "$app" ] || { echo "$app 폴더가 없습니다." >&2; exit 1; }
  files="$( { git -c core.quotePath=false ls-files -- "$app"; git -c core.quotePath=false ls-files --others --exclude-standard -- "$app"; } | sort -u)"
  badf="$(printf '%s\n' "$files" | grep -E '(^|/)\.env($|\.)|\.(pem|key|p12|jks|keystore)$' | grep -Ev '(^|/)\.env\.example$')"
  hits="$(printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -IHn '' "$f" 2>/dev/null
  done | secret_grep | cut -d: -f1,2 | head -n 5)"
  [ -z "$badf$hits" ] && exit 0
  echo "비밀값 검사에 걸림(값은 보이지 않게 파일:줄만):${badf:+
$badf}${hits:+
$hits}"
  exit 1
fi

input="$(cat)"
# 명령 문자열만 꺼낸다 (JSON 이스케이프된 따옴표·역슬래시를 대략 풀어 줌)
cmd="$(printf '%s' "$input" | tr '\n' ' ' | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' \
  | sed 's/"[[:space:]]*,[[:space:]]*"[a-z_]*"[[:space:]]*:.*//; s/"[[:space:]]*}.*//' | sed 's/\\"/"/g; s/\\\\/\\/g')"
[ -z "$cmd" ] && exit 0

block() {
  echo "훅이 막았습니다: $1
이 규칙은 CLAUDE.md '절대 하지 않을 것'입니다. 우회하지 말고, 정말 필요하면 사장에게 이유를 설명하고 사장이 직접 '!' 한 줄로 실행하게 하세요." >&2
  exit 2
}

# ---- 1. 되돌릴 수 없는 git·GitHub 동작 ----
pushseg="$(printf '%s' "$cmd" | grep -Eo 'git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+push[^;&|]*')"
if [ -n "$pushseg" ]; then
  printf '%s' "$pushseg" | grep -Eq '(^|[[:space:]])(--force|--force-with-lease|--force-if-includes|-f|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]=]|$)' \
    && block "강제 푸시(--force)는 다른 컴퓨터의 작업을 지울 수 있습니다."
  printf '%s' "$pushseg" | grep -Eq '[[:space:]]\+[^[:space:]]+' \
    && block "'+브랜치' 형태의 푸시는 강제 푸시와 같습니다."
  printf '%s' "$pushseg" | grep -Eq '(--delete|--mirror|[[:space:]]:[^[:space:]]+)' \
    && block "원격 브랜치 삭제·미러 푸시는 막혀 있습니다."
  pushq="$(printf '%s' "$pushseg" | tr -d "\"'")"   # 따옴표로 감싸 피하지 못하게
  printf '%s' "$pushq" | grep -Eq '[^[:space:]]:(refs/heads/)?(main|master)([[:space:]]|$)' \
    && block "다른 브랜치를 main으로 바로 푸시(…:main)하면 테스트 확인을 건너뜁니다. main에서 합친 뒤 그냥 git push 하세요."
  # 임시 브랜치에서 그냥 push 할 때 실제로 어디로 가는지(@{push})까지 본다 — 추적 설정이 main이면 막음
  case "$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" in
    wip/*)
      for dest in "$(git rev-parse --abbrev-ref '@{push}' 2>/dev/null)" "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; do
        case "$dest" in */main|*/master|main|master) block "이 임시 브랜치는 추적·push 대상이 $dest 입니다(main으로 갈 수 있음). 'git push -u origin <같은 wip 이름>'으로 올리세요." ;; esac
      done ;;
  esac
fi
normq="$(printf '%s' "$cmd" | tr -d "\"'\\\\")"   # 따옴표·역슬래시로 감싸 피하지 못하게
printf '%s' "$normq" | grep -Eiq '(^|[[:space:]=])--no-v[a-z-]*([[:space:]=]|$)|hooks[[:space:]_.-]*path' \
  && block "git 훅을 건너뛰거나(--no-verify) 훅 경로(core.hooksPath)를 바꾸면 main push 전 테스트 확인(.githooks/pre-push)이 꺼집니다."
printf '%s' "$cmd" | grep -Eq 'push\.default|remote\.[^[:space:]]*\.push|branch\.[^[:space:]]*\.merge' \
  && block "푸시·추적 설정(push.default·remote.*.push·branch.*.merge)을 바꾸면 임시 브랜치가 main으로 갈 수 있습니다. 설정은 그대로 두세요."
# 임시 브랜치(wip/…)는 테스트가 실패해도 커밋되므로(check-tests 예외), 다른 브랜치로 가져올 때는
# 한 커밋으로 묶어(--squash) 다시 커밋하게 한다 — 그 git commit 에서 check-tests가 테스트를 돌린다.
# 실행 전 브랜치로 판단하면 이어 붙인 명령(git switch main && git merge …)에 속으므로, 지금 브랜치와 상관없이 늘 검사한다.
cmdq="$(printf '%s' "$cmd" | tr -d "\"'")"
printf '%s\n' "$cmdq" | grep -Eo 'git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+(merge|pull|rebase|cherry-pick)[^;&|]*' | while IFS= read -r seg; do
  printf '%s' "$seg" | grep -q 'wip/' || continue
  printf '%s' "$seg" | grep -Eq '[[:space:]]merge[[:space:]]' && printf '%s' "$seg" | tr ' ' '\n' | grep -qx -- '--squash' && continue
  exit 7
done
[ $? -eq 7 ] && block "임시 브랜치(wip/…)를 그대로 합치면 테스트가 실패한 커밋이 들어옵니다. 'git merge --squash wip/<이름>' 뒤 'git commit -m \"…\"'로 합치세요(커밋 때 테스트 확인). (임시 브랜치에서 받을 때는 그냥 git pull)"
# main을 임시 브랜치 쪽으로 옮기는 길 막기: 브랜치 이름 바꾸기·강제 옮기기·update-ref·reset 으로 wip 커밋을 main에
printf '%s' "$cmdq" | grep -Eq 'git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+branch[[:space:]]+[^;&|]*(-m|-M|-f|-F|--force|--move)[^;&|]*(main|master)' \
  && block "브랜치 이름 바꾸기·강제 옮기기로 main을 바꾸면 테스트 확인을 건너뜁니다."
printf '%s' "$cmdq" | grep -Eq 'git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+update-ref[^;&|]*(main|master)' \
  && block "update-ref로 main을 바로 옮기는 것은 막혀 있습니다."
printf '%s' "$cmdq" | grep -Eq 'git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+reset[^;&|]*wip/' \
  && block "reset으로 임시 브랜치(wip/…) 커밋을 가져오면 테스트 확인을 건너뜁니다. 'git merge --squash'로 합치세요."
printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(filter-branch|filter-repo)\b' \
  && block "커밋 기록 고쳐 쓰기(filter-branch/filter-repo)는 막혀 있습니다."
printf '%s' "$cmd" | grep -Eq 'gh[^;&|]*[[:space:]]repo[[:space:]]+(delete|archive)\b' \
  && block "저장소 삭제·보관은 사장만 할 수 있습니다."
printf '%s' "$cmd" | grep -Eq 'gh[^;&|]*[[:space:]]api[^;&|]*(-X|--method)[[:space:]]*DELETE[^;&|]*repos/' \
  && block "GitHub API로 저장소를 지우는 요청은 막혀 있습니다."

# ---- 2. 커밋 직전 검사 ----
printf '%s' "$cmd" | grep -Eq 'git([[:space:]]+[^[:space:];&|]+)*[[:space:]]+commit\b' || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# 커밋될 파일 목록: 스테이지된 것 + (같은 명령에 git add / commit -a 가 있으면) 아직 안 올린 변경까지
# 한글 등 비ASCII 경로를 git이 "\354\243..." 처럼 따옴표로 감싸 출력하면 아래 패턴 검사를 빠져나가므로 끈다.
g() { git -c core.quotePath=false "$@"; }
files="$(g diff --cached --name-only --diff-filter=ACMR)"
diffs="$(g diff --cached --diff-filter=ACMR -U0)"
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+add\b|commit[^;&|]*[[:space:]]-[a-zA-Z]*a'; then
  files="$files
$(g diff --name-only --diff-filter=ACMR)
$(g ls-files --others --exclude-standard)"
  diffs="$diffs
$(g diff --diff-filter=ACMR -U0)"
  while IFS= read -r f; do
    [ -f "$f" ] && diffs="$diffs
+++ b/$f
$(sed 's/^/+/' "$f" 2>/dev/null)"
  done <<< "$(g ls-files --others --exclude-standard)"
fi
# 따옴표·줄바꿈 같은 특수문자가 든 경로는 그래도 따옴표로 감싸지므로 앞뒤 따옴표를 벗긴다.
files="$(printf '%s\n' "$files" | sed '/^$/d; s/^"//; s/"$//' | sort -u)"

# 2-1. 올리면 안 되는 파일
bad_files="$(printf '%s\n' "$files" | grep -E '(^|/)\.env($|\.)|\.(pem|key|p12|jks|keystore)$|(^|/)(node_modules|dist|build|\.venv|venv|__pycache__)/' | grep -Ev '(^|/)\.env\.example$')"
[ -n "$bad_files" ] && block "커밋하면 안 되는 파일이 있습니다(.env·키 파일·다시 만들 수 있는 폴더):
$bad_files
→ git restore --staged <파일> 로 빼고, 필요하면 .gitignore에 추가하세요. 값은 .env.example에 이름만."

# 2-1b. 실제 업무 데이터 파일 (주문서·고객 명단·원가표 등이 담길 수 있음)
#   테스트용 가짜 견본(tests/fixtures/ 아래)만 허용한다. samples/ 폴더는 통째로 막는다.
data_files="$(printf '%s\n' "$files" | grep -Ei '\.(xlsx|xlsm|xls|csv|tsv|hwp|hwpx|numbers)$|(^|/)samples/' | grep -Ev '(^|/)tests/fixtures/')"
[ -n "$data_files" ] && block "실제 업무 데이터일 수 있는 파일이 커밋에 들어 있습니다:
$data_files
→ git restore --staged <파일> 로 빼세요. 실제 파일은 apps/<앱>/samples/(커밋 안 함)에 두고,
  테스트에는 칸·형식은 같고 내용은 가짜인 견본을 만들어 tests/fixtures/ 에 두세요. (/build-app '견본 파일' 절)"

# 2-2. 비밀값 패턴과 컴퓨터 전용 경로 (추가된 줄만, 훅 파일 자신은 제외)
added="$(printf '%s\n' "$diffs" | awk '
  /^\+\+\+ / { f=$2; sub(/^b\//,"",f); next }
  /^\+/ && f !~ /^\.claude\/hooks\// { print f ": " substr($0,2) }')"

secrets="$(printf '%s\n' "$added" | secret_grep | head -n 5)"
[ -n "$secrets" ] && block "비밀값으로 보이는 내용이 커밋에 들어 있습니다:
$secrets
→ 값은 .env로 옮기고 코드에서는 환경변수로 읽으세요. (오탐이면 사장에게 확인받으세요)"

paths="$(printf '%s\n' "$added" | grep -Ev '^[^:]*\.md: ' | grep -E \
  -e '[A-Za-z]:\\\\?Users\\\\?' \
  -e '/Users/[A-Za-z0-9._-]+/' \
  -e '/home/[A-Za-z0-9._-]+/' \
  | head -n 5)"
[ -n "$paths" ] && block "특정 컴퓨터에만 있는 경로가 코드·설정에 들어 있습니다:
$paths
→ 저장소 기준 상대 경로로 바꾸세요."

exit 0

# 교차 리뷰(필수): 이번 작업의 변경분을 만든 AI(Claude)와 다른 AI에게 리뷰받는다. Codex와 Gemini 둘 다 필수.
# 사용: 저장소 맨 위에서
#   bash .claude/skills/build-app/cross-review.sh apps/<앱> [기준] [gemini|codex]   (셋째 값이 없으면 gemini)
#   bash .claude/skills/build-app/cross-review.sh snapshot apps/<앱>
#     → 지금 상태(커밋 안 한 것·새 파일 포함)를 찍어 해시를 출력. 실제 스테이지(index)는 건드리지 않는다.
#       4단계에서 plan.md 단계를 시작할 때 찍어 progress.md에 적고, 그 단계가 통과하면 그 해시를 기준으로 Codex 검수.
#   기준: 커밋 해시나 snapshot 해시. 5단계는 HANDOFF의 "리뷰 기준"(4단계 시작 직전 커밋).
#         없으면 커밋 전 변경분(HEAD 기준) → 브랜치 작업이면 main...HEAD 순으로 고른다.
# 결과: apps/<앱>/docs/review_input.txt (보낸 내용, 커밋 안 함)
#       apps/<앱>/docs/review_result.md (Gemini) / apps/<앱>/docs/review_codex.md (Codex)
# 주의: 앱 코드가 Google(Gemini)·OpenAI(Codex) 서비스로 보내진다. .env·키 파일·samples/는 빼고 보낸다.
#       도구가 없으면 실패로 끝난다(건너뛰지 않음).

# 지금 상태를 임시 인덱스로 찍어 커밋 객체 해시를 출력 (실제 index·작업 폴더는 그대로)
snapshot() {
  local app="$1" idx tree
  idx="$(mktemp)"
  GIT_INDEX_FILE="$idx" git read-tree HEAD || { rm -f "$idx"; return 1; }
  GIT_INDEX_FILE="$idx" git add -A -- "$app" || { rm -f "$idx"; return 1; }
  tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
  rm -f "$idx"
  git commit-tree "$tree" -p HEAD -m "cross-review snapshot ($app)"
}

if [ "$1" = "snapshot" ]; then
  app="${2%/}"
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "사용법: bash .claude/skills/build-app/cross-review.sh snapshot apps/<앱>" >&2; exit 1
  fi
  h="$(snapshot "$app")" || { echo "기준점을 찍지 못했습니다." >&2; exit 1; }
  echo "$h"
  exit 0
fi

app="${1%/}"
base="$2"
reviewer="${3:-gemini}"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "사용법: bash .claude/skills/build-app/cross-review.sh apps/<앱> [기준] [gemini|codex]" >&2
  exit 1
fi

case "$reviewer" in
  gemini)
    if ! command -v gemini >/dev/null 2>&1; then
      cat >&2 <<'MSG'
교차 리뷰는 필수인데 Gemini CLI가 없습니다. 사장에게 설치를 부탁하고 다시 실행하세요.
  1. Node.js:    winget install --id OpenJS.NodeJS.LTS -e   (Mac: brew install node)
  2. Gemini CLI: npm install -g @google/gemini-cli
  3. API 키:    https://aistudio.google.com/apikey 에서 무료 키를 만들고 PowerShell에서
     [Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "<키>", "User")  (터미널을 새로 열어야 적용)
     (Google 계정 로그인 방식은 2026-10부터 개인 무료 사용이 막혀 안 됨)
MSG
      exit 1
    fi ;;
  codex)
    if ! command -v codex >/dev/null 2>&1; then
      cat >&2 <<'MSG'
교차 리뷰는 필수인데 Codex CLI가 없습니다. 사장에게 설치·로그인을 부탁하고 다시 실행하세요.
  1. Node.js:   winget install --id OpenJS.NodeJS.LTS -e   (Mac: brew install node)
  2. Codex CLI: npm install -g @openai/codex
  3. 로그인:    codex login   (브라우저에서 ChatGPT 계정으로 로그인)
MSG
      exit 1
    fi ;;
  *) echo "셋째 값은 gemini 또는 codex 입니다 (받은 값: $reviewer)" >&2; exit 1 ;;
esac

# 1. 리뷰 대상: 변경분 (기준 → 지금 상태 snapshot. 커밋 안 한 것·새 파일까지 diff에 들어간다)
if [ -n "$base" ]; then
  from="$base"; to="$(snapshot "$app")" || exit 1
elif [ -n "$(git status --porcelain -- "$app")" ]; then
  from="HEAD"; to="$(snapshot "$app")" || exit 1
elif [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  from="$(git merge-base main HEAD)"; to="HEAD"
else
  echo "변경분이 없습니다. 이번 작업을 시작하기 직전 커밋을 두 번째 값으로 주세요 (예: ... apps/<앱> a1b2c3d)" >&2
  exit 1
fi

set -f            # 파일 이름의 *, ? 를 풀지 않음
IFS='
'          # 파일 이름은 줄 단위로만 나눔 (띄어쓰기 허용)

docs="$app/docs"
input="$docs/review_input.txt"
if [ "$reviewer" = "codex" ]; then result="$docs/review_codex.md"; else result="$docs/review_result.md"; fi
mkdir -p "$docs"

# 밖으로 보내면 안 되는 파일: .env(.env.example 포함 전부)·키 파일·실제 업무 파일(samples/)
secret_re='(^|/)\.env($|\.)|\.(pem|key|p12|jks|keystore)$|(^|/)samples/'
excl=":(exclude,glob)**/.env :(exclude,glob)**/.env.* :(exclude,glob)**/*.pem :(exclude,glob)**/*.key :(exclude,glob)**/*.p12 :(exclude,glob)**/*.jks :(exclude,glob)**/*.keystore :(exclude,glob)**/samples/** :(exclude,glob)**/docs/** :(exclude,glob)**/HANDOFF.md :(exclude,glob)**/node_modules/**"
IFS=' ' read -r -a excl_arr <<< "$excl"

changed=$(git diff --name-only "$from" "$to" -- "$app" "${excl_arr[@]}" | grep -v -e '/docs/' -e 'HANDOFF.md$' -e 'node_modules/' -e '/dist/' -e '/build/' | grep -Ev "$secret_re")
changed=$(printf '%s\n' "$changed" | sed '/^$/d' | sort -u)
if [ -z "$changed" ]; then
  echo "리뷰할 코드 변경이 없습니다 (기준: $from)" >&2
  exit 1
fi

# 변경된 파일을 import·호출하는 주요 파일 (파일당 최대 3개)
related=""
for f in $changed; do
  stem=$(basename "$f"); stem="${stem%.*}"
  [ ${#stem} -lt 3 ] && continue
  users=$(grep -rlE "(import|require|from|include|src=|href=).*[/.\"' ]$stem([.\"' ;)]|$)" "$app" \
            --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=docs --exclude-dir=.git --exclude-dir=samples 2>/dev/null \
          | sed 's#^\./##' | grep -vxF "$f" | head -3)
  related="$related
$users"
done
related=$(printf '%s\n' "$related" | sed '/^$/d' | grep -Ev "$secret_re" | sort -u | grep -vxF -f <(printf '%s\n' "$changed"))

{
  echo "# 변경분 (git diff $from -- $app)"
  git diff "$from" "$to" -- "$app" "${excl_arr[@]}"
  echo
  echo "# 변경된 파일 전체"
  for f in $changed; do
    case "$f" in "$app"/*) ;; *) continue ;; esac
    case "$f" in *..*) continue ;; esac
    [ -f "$f" ] || continue
    echo "===== $f ====="
    cat "$f"
    echo
  done
  if [ -n "$related" ]; then
    echo "# 변경된 파일을 import·호출하는 주요 파일"
    for f in $related; do
      case "$f" in "$app"/*) ;; *) continue ;; esac
      case "$f" in *..*) continue ;; esac
      echo "===== $f ====="
      cat "$f"
      echo
    done
  fi
} > "$input"

prompt="너는 시니어 코드 리뷰어다. 아래 변경사항을 리뷰해라.
- 버그, 보안 문제, 예외 처리 누락, 성능 문제만 지적할 것. 스타일·네이밍 같은 취향 문제는 제외.
- 각 항목마다 [심각도: 높음/중간/낮음], 파일명과 줄 번호, 문제 이유, 수정 제안을 적을 것.
- 확실하지 않은 지적은 '추정'이라고 표시할 것.
- 문제가 없으면 '문제 없음'이라고만 답할 것.
- 파일을 만들거나 고치지 말고, 답만 할 것."

# 2. 리뷰 요청 (1라운드만). 빈 임시 폴더에서 실행: 보낸 내용만 보고 저장소의 다른 파일은 못 본다.
sandbox=$(mktemp -d)
result_abs="$PWD/$result"
if [ "$reviewer" = "codex" ]; then
  echo "== Codex 리뷰 중... (몇 분 걸릴 수 있음)"
  # -s read-only: 명령을 실행해도 파일을 못 고치는 모드 / --ephemeral: 세션 기록을 남기지 않음
  # -o: 마지막 답만 결과 파일로 / 프롬프트 + 표준입력(review_input)이 함께 전달됨
  if ! codex exec -s read-only --skip-git-repo-check --ephemeral --color never \
        -C "$sandbox" -o "$result_abs" "$prompt" < "$input" > "$sandbox.log" 2>&1; then
    rm -rf "$sandbox"
    echo "Codex 실행 실패. 'codex login status'로 로그인을 확인하세요. 실행 기록 끝부분:" >&2
    tail -n 5 "$sandbox.log" >&2; rm -f "$sandbox.log"
    exit 1
  fi
  rm -f "$sandbox.log"
else
  echo "== Gemini 리뷰 중... (몇 분 걸릴 수 있음)"
  model="${GEMINI_MODEL:-gemini-3-flash-preview}"   # 무료 키는 pro 모델 사용량이 0이라 flash를 기본으로
  if ! cat "$input" | (cd "$sandbox" && gemini --skip-trust -m "$model" -p "$prompt") > "$result_abs"; then
    rm -rf "$sandbox"
    echo "Gemini 실행 실패 (모델: $model). GEMINI_API_KEY가 설정됐는지, 모델 이름이 바뀌지 않았는지 확인하세요. 다른 모델: GEMINI_MODEL=<이름> bash ... ($result 확인)" >&2
    exit 1
  fi
fi

rm -rf "$sandbox"
if [ ! -s "$result_abs" ]; then
  echo "리뷰 결과가 비어 있습니다 ($result). 다시 실행하거나 사장에게 알리세요." >&2
  exit 1
fi
echo "교차 리뷰 저장($reviewer): $result (보낸 내용: $input, 기준: $from)"

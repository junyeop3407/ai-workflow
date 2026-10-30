# 교차 리뷰(필수): 이번 작업의 변경분을 Gemini CLI에게 리뷰받는다.
# 사용: 저장소 맨 위에서  bash .claude/skills/build-app/cross-review.sh apps/<앱> [기준커밋]
#   기준커밋: 이번 작업을 시작하기 직전 커밋(HANDOFF의 "리뷰 기준"). 없으면
#            커밋 전 변경분(git diff HEAD) → 브랜치 작업이면 git diff main...HEAD 순으로 고른다.
# 결과: apps/<앱>/docs/review_input.txt (리뷰에 보낸 내용, 커밋 안 함)
#       apps/<앱>/docs/review_result.md (Gemini 리뷰)
# 주의: 앱 코드가 Google 서비스로 보내진다. Gemini가 없으면 실패로 끝난다(건너뛰지 않음).

app="${1%/}"
base="$2"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "사용법: bash .claude/skills/build-app/cross-review.sh apps/<앱> [기준커밋]" >&2
  exit 1
fi

if ! command -v gemini >/dev/null 2>&1; then
  cat >&2 <<'MSG'
교차 리뷰는 필수인데 Gemini CLI가 없습니다. 설치하고 다시 실행하세요.
  1. Node.js:    winget install --id OpenJS.NodeJS.LTS -e   (Mac: brew install node)
  2. Gemini CLI: npm install -g @google/gemini-cli
  3. 로그인:     gemini   (처음 한 번 실행해 Google 계정으로 로그인)
MSG
  exit 1
fi

# 1. 리뷰 대상: 변경분
if [ -n "$base" ]; then
  range="$base"
elif [ -n "$(git status --porcelain -- "$app")" ]; then
  range="HEAD"
elif [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  range="main...HEAD"
else
  echo "변경분이 없습니다. 이번 작업을 시작하기 직전 커밋을 두 번째 값으로 주세요 (예: ... apps/<앱> a1b2c3d)" >&2
  exit 1
fi

set -f            # 파일 이름의 *, ? 를 풀지 않음
IFS='
'          # 파일 이름은 줄 단위로만 나눔 (띄어쓰기 허용)

docs="$app/docs"
input="$docs/review_input.txt"
result="$docs/review_result.md"
mkdir -p "$docs"

changed=$(git diff --name-only $range -- "$app" | grep -v -e '/docs/' -e 'HANDOFF.md$' -e 'node_modules/' -e '/dist/' -e '/build/')
changed="$changed
$(git ls-files --others --exclude-standard -- "$app" | grep -v -e '/docs/' -e 'HANDOFF.md$')"
changed=$(printf '%s\n' "$changed" | sed '/^$/d' | sort -u)
if [ -z "$changed" ]; then
  echo "리뷰할 코드 변경이 없습니다 (기준: $range)" >&2
  exit 1
fi

# 변경된 파일을 import·호출하는 주요 파일 (파일당 최대 3개)
related=""
for f in $changed; do
  stem=$(basename "$f"); stem="${stem%.*}"
  [ ${#stem} -lt 3 ] && continue
  users=$(grep -rlE "(import|require|from|include|src=|href=).*[/.\"' ]$stem([.\"' ;)]|$)" "$app" \
            --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=docs --exclude-dir=.git 2>/dev/null \
          | sed 's#^\./##' | grep -vxF "$f" | head -3)
  related="$related
$users"
done
related=$(printf '%s\n' "$related" | sed '/^$/d' | sort -u | grep -vxF -f <(printf '%s\n' "$changed"))

{
  echo "# 변경분 (git diff $range -- $app)"
  git diff $range -- "$app"
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

# 2. Gemini에게 리뷰 요청 (1라운드만)
echo "== Gemini 리뷰 중... (몇 분 걸릴 수 있음)"
if ! cat "$input" | gemini -p "너는 시니어 코드 리뷰어다. 아래 변경사항을 리뷰해라.
- 버그, 보안 문제, 예외 처리 누락, 성능 문제만 지적할 것. 스타일·네이밍 같은 취향 문제는 제외.
- 각 항목마다 [심각도: 높음/중간/낮음], 파일명과 줄 번호, 문제 이유, 수정 제안을 적을 것.
- 확실하지 않은 지적은 '추정'이라고 표시할 것.
- 문제가 없으면 '문제 없음'이라고만 답할 것." > "$result"; then
  echo "Gemini 실행 실패. 로그인이 필요할 수 있습니다: gemini 를 한 번 실행해 보세요. ($result 확인)" >&2
  exit 1
fi

echo "교차 리뷰 저장: $result (보낸 내용: $input, 기준: $range)"

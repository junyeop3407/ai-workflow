# 교차 리뷰: 다른 회사 AI(Codex CLI, Gemini CLI)에게 앱 코드와 테스트를 리뷰받는다.
# 사용: 저장소 맨 위에서  bash .claude/skills/build-app/cross-review.sh apps/<앱>
# 결과: apps/<앱>/docs/cross-review.md 에 도구별로 저장. 깔린 도구가 없으면 설치 방법만 알리고 끝낸다.
# 주의: 앱 코드가 그 회사 서비스로 보내진다(사용자가 교차 리뷰를 쓰기로 정한 것).

app="${1%/}"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "사용법: bash .claude/skills/build-app/cross-review.sh apps/<앱>" >&2
  exit 1
fi
out="$app/docs/cross-review.md"
mkdir -p "$app/docs"

prompt='너는 이 폴더의 앱을 처음 보는 리뷰어다. 파일을 고치지 말고 읽기만 하라.
docs/requirements.md 와 docs/tests.md(사용자가 승인한 테스트 목록)를 기준으로,
앱 코드와 tests/ 를 읽고 사용자가 실제로 겪을 진짜 문제만 찾아라:
잘못된 계산, 데이터 손실, 날짜·경계 값 오류, 보안(XSS 등), 요구사항 미충족,
설명보다 약한 테스트. 꾸밈·취향 지적은 빼라.
한국어로, 문제마다 "심각도(높음/중간/낮음) · 문제 · 재현 방법 · 고치는 법"을 쓰고,
마지막 줄에 한 줄 판정을 써라.'

ran=0
{
  echo "# 교차 리뷰 ($(date +%Y-%m-%d))"
  echo
  echo "다른 회사 AI의 리뷰. Claude 리뷰(review.md)와 겹치지 않는 지적을 특히 볼 것."
} > "$out.tmp"

run_tool() {
  name="$1"; shift
  echo "== $name 리뷰 중... (몇 분 걸릴 수 있음)"
  {
    echo
    echo "## $name"
    echo
  } >> "$out.tmp"
  if (cd "$app" && "$@") >> "$out.tmp" 2>&1; then
    ran=$((ran + 1))
  else
    echo "($name 실행 실패. 로그인이 필요하거나 명령이 바뀌었을 수 있음: \`$name --help\` 확인)" >> "$out.tmp"
  fi
}

if command -v codex >/dev/null 2>&1; then
  run_tool codex codex exec "$prompt"
fi
if command -v gemini >/dev/null 2>&1; then
  run_tool gemini gemini -p "$prompt"
fi

if ! command -v codex >/dev/null 2>&1 && ! command -v gemini >/dev/null 2>&1; then
  rm -f "$out.tmp"
  cat <<'MSG'
교차 리뷰 도구가 없어서 건너뜁니다. 쓰려면 하나 이상 설치하세요 (Node.js 필요: winget install --id OpenJS.NodeJS.LTS -e):
  - Codex CLI (OpenAI):  npm install -g @openai/codex   → 처음 한 번 codex 실행해 로그인
  - Gemini CLI (Google): npm install -g @google/gemini-cli → 처음 한 번 gemini 실행해 로그인
MSG
  exit 0
fi

mv "$out.tmp" "$out"
echo "교차 리뷰 저장: $out (성공한 도구 $ran개)"

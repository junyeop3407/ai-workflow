#!/usr/bin/env bash
# 승인된 테스트 잠그기 — **사장만 실행한다.** (Claude가 실행하면 protect-tests.sh가 막는다)
# 사용: 저장소 맨 위에서  ! bash .claude/hooks/approve-tests.sh apps/<앱>
#   3단계에서 테스트 목록을 승인하고 Claude가 테스트 코드를 다 쓴 뒤 한 번,
#   승인된 테스트를 고치도록 허락한 뒤 다시 한 번.
# 결과: apps/<앱>/tests/.approved 에 "<sha256>  <저장소 기준 경로>" 한 줄씩.
#   준비 코드(conftest.py, run.sh, fixtures/, helpers/)와 리뷰 회귀 테스트(test_review_fixes*)는 넣지 않는다.
#   해시는 줄바꿈 차이(CRLF/LF)에 흔들리지 않게 \r 을 지운 내용으로 계산한다.

app="${1%/}"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "git 저장소 안에서 실행하세요." >&2; exit 1; }
cd "$root" || exit 1
case "$app" in apps/*) ;; *) echo "사용법: bash .claude/hooks/approve-tests.sh apps/<앱>" >&2; exit 1 ;; esac
if [ ! -d "$app/tests" ]; then
  echo "$app/tests 폴더가 없습니다." >&2; exit 1
fi

files="$(find "$app/tests" -type f \
  ! -name .approved ! -name conftest.py ! -name run.sh ! -name 'test_review_fixes*' \
  ! -name '*.pyc' ! -name '.DS_Store' \
  ! -path '*/fixtures/*' ! -path '*/helpers/*' ! -path '*/node_modules/*' ! -path '*/__pycache__/*' \
  | sort)"
if [ -z "$files" ]; then
  echo "$app/tests 에 잠글 테스트 파일이 없습니다." >&2; exit 1
fi

out="$app/tests/.approved"
{
  echo "# 승인된 테스트 목록 — 사장이 approve-tests.sh로만 만든다. 직접 고치지 않는다."
  echo "# 승인: $(date '+%Y-%m-%d %H:%M')"
  while IFS= read -r f; do
    h="$(tr -d '\r' < "$f" | sha256sum | cut -c1-64)"
    printf '%s  %s\n' "$h" "$f"
  done <<< "$files"
} > "$out"

echo "잠금 완료: $out"
sed -n 's/^[0-9a-f]\{64\}  /  - /p' "$out"

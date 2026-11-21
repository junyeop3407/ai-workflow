#!/usr/bin/env bash
# 기획서 비판(req 노드, 필수): 기획서를 만든 AI(Claude)와 다른 AI(안티그래비티 = Gemini)가 ★기획 검토 전에 한 번 비판한다.
# 사용: 저장소 맨 위에서  bash .claude/skills/build-app/doc-review.sh apps/<앱>
# 보내는 것: apps/<앱>/docs/requirements.md 만 (견본 파일·samples/·.env 는 보내지 않는다)
# 결과: apps/<앱>/docs/review_req.md — 맨 위 "## Gemini 지적" 원문. 그 아래 "## Claude 판단"은 Claude가 지적마다
#       [맞음]/[틀림]/[사장 확인] + 반영한 곳을 한 줄씩 적는다(graph.md "리뷰 판단 줄" 형식).
# 1라운드만. 도구가 없으면 실패로 끝난다(건너뛰지 않음 — CLAUDE.md "필요한 것이 없을 때").
# agy 는 headless 에서 도구 권한을 물을 수 없어 자동 거부되므로, 문서는 프롬프트 안에 넣고 빈 임시 폴더에서 부른다.

app="${1%/}"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "사용법: bash .claude/skills/build-app/doc-review.sh apps/<앱>" >&2; exit 1
fi
doc="$app/docs/requirements.md"
[ -s "$doc" ] || { echo "기획서가 없거나 비어 있습니다: $doc" >&2; exit 1; }
if ! command -v agy >/dev/null 2>&1; then
  cat >&2 <<'MSG'
기획서 비판은 필수인데 안티그래비티(agy)가 없습니다. 사장에게 설치·로그인을 부탁하고 다시 실행하세요.
  1. https://antigravity.google 에서 Antigravity 설치 (agy 명령이 함께 깔림)
  2. 터미널을 새로 열고  agy  를 한 번 실행해 Google 계정으로 로그인
MSG
  exit 1
fi
if [ "$(wc -c < "$doc")" -gt 24000 ]; then
  echo "기획서가 너무 깁니다(24KB 넘음). 기획서는 사장이 읽는 문서라 짧아야 합니다 — 줄인 뒤 다시 실행하세요." >&2; exit 1
fi

prompt="너는 까다로운 제품 기획 검토자다. 도구를 쓰지 말고 답만 해라.
아래 기획서를 읽고, 개발을 시작하기 전에 고쳐야 할 것만 지적해라. 문장 다듬기·취향 지적은 하지 마라.
보는 것:
1. 성공 기준이 측정 가능한가(숫자·관찰 가능한 결과)
2. 빈칸 점검표에서 '정함'이라는데 실제로는 모호한 칸
3. 수용 기준(F1-1 …)이 '언제/조건 → 보이는 결과'로 테스트 가능한가, 빠진 예외(빈 값·실패·끊김·권한 없음)
4. 기능끼리 모순, 하지 않을 것과 기능의 충돌
5. 돈·메시지 발송·삭제처럼 되돌리기 어려운 동작에 확인 절차가 있는가
6. 사용자가 실제로 원하는 결과에 비해 빠진 핵심 기능, 또는 첫 버전에 필요 없는 기능
7. [1차] 기능만으로 사용자가 처음부터 끝까지 한 번 쓸 수 있는가, [놀람] 기능이 1차에 섞여 범위를 키우지 않는가
8. 수용 기준의 '예:' 값이 규칙과 맞는가(예시와 규칙이 서로 다르면 지적)
9. 출시 안내문이 약속하는 것을 1차 기능이 다 채우는가, 안내문에 없는 기능이 1차에 있는가
형식: 지적마다 한 줄 '- [높음|중간|낮음] <어디> — <문제> / 제안: <고칠 방법>'. 확실하지 않으면 '추정'. 문제가 없으면 '문제 없음'만.
=== 기획서 ===
$(cat "$doc")"

out="$app/docs/review_req.md"
sandbox="$(mktemp -d)"
echo "== Gemini(agy) 기획서 비판 중... (1~3분)"
if ! res="$(cd "$sandbox" && agy -p "$prompt" --disable-slash-commands --print-timeout "${AGY_TIMEOUT:-5m}" < /dev/null 2>"$sandbox.err")"; then
  echo "agy 실행 실패. 로그인 상태를 확인하세요(agy 를 직접 한 번 실행). 끝부분:" >&2
  tail -n 5 "$sandbox.err" >&2; rm -rf "$sandbox" "$sandbox.err"; exit 1
fi
rm -rf "$sandbox" "$sandbox.err"
res="$(printf '%s\n' "$res" | grep -v '^warning:')"
if [ -z "$(printf '%s' "$res" | tr -d '[:space:]')" ]; then
  echo "비판 결과가 비어 있습니다. 한 번만 다시 실행하고, 또 비면 사장에게 알리세요(ai-team.md: 재시도 1번)." >&2; exit 1
fi
{ echo "# 기획서 비판 — Gemini(agy) $(date '+%Y-%m-%d %H:%M')"; echo
  echo "## Gemini 지적"; printf '%s\n' "$res"; echo
  echo "## Claude 판단"; echo "<!-- 지적마다: - [맞음|틀림|사장 확인] <지적 요약> — 해결: docs/requirements.md:<줄> 또는 이유 -->"; } > "$out"
echo "기획서 비판 저장: $out — '## Claude 판단'을 채우고, [맞음]은 기획서에 반영한 뒤 req 를 pass 하세요."

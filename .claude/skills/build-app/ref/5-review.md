# 5단계 리뷰 (qa·cx·gm) — 이 노드에 들어갈 때 읽는다

**QA팀 순서**: ① `qa-reviewer` 에이전트(구현 대화를 넘기지 않음)에게 앱 폴더 경로·`docs/tests.md`·바뀐 준비 코드 목록만 주고 리뷰 → `docs/review.md` (언어별로 `ecc:react-reviewer`·`ecc:java-reviewer`도, 지적은 review.md에 합침) → ② Codex 교차 리뷰 → ③ Gemini 교차 리뷰, 각 1라운드 → 셋에서 나온 진짜 문제만 고치고(5회 루프) 테스트 다시 실행.

## 교차 리뷰 (필수 — 만든 AI와 다른 AI 두 곳: Codex + Gemini)
이번 작업에서 수정한 코드를 Claude가 아닌 AI 두 곳에 검수받는다. **둘 다 건너뛰지 않는다.**

| 언제 | 누가 | 범위 | 결과 파일 |
|---|---|---|---|
| 4단계, plan.md 단계 하나가 통과할 때마다 | Codex | 그 단계 변경분(기준 = 단계 시작 때 찍은 `snapshot` 해시) | `docs/review_codex.md` (덮어씀) |
| 5단계 ② cx | Codex `final` (교차 + 적대적 리뷰) | 4단계 시작부터 전체(기준 = HANDOFF `리뷰 기준:`) | `docs/review_codex.md` |
| 5단계 ③ gm | Gemini `final` (교차 + 기획서 대비 빠진 기능) | 같은 전체 + `requirements.md` | `docs/review_result.md` |
5단계 순서는 **qa-reviewer(Claude) → Codex → Gemini**, 각 1라운드.

1. **실행**: `bash .claude/skills/build-app/cross-review.sh apps/<앱> <기준> [codex|gemini] [final]` (셋째 값을 안 주면 gemini). **5단계 cx·gm은 반드시 `final`** — 배포 전 적대적 리뷰·기획 대비 확인을 여기서 한 번에 하므로 `/codex:adversarial-review`·`agy -p` 기획 대비를 따로 돌리지 않는다(ai-team.md "겹칠 때는 한 번만"). 4단계 cb·cf는 `final` 없이. cb·cf가 기능 끝 리뷰이므로 `/codex:review`도 따로 안 돌린다.
   - 기준점 찍기(4단계 단계 시작 때): `bash .claude/skills/build-app/cross-review.sh snapshot apps/<앱>` → 나온 해시를 `progress.md`에. 실제 스테이지는 건드리지 않는다.
   - 리뷰 기준(5단계)은 4단계 구현을 시작하기 직전 커밋. 4단계를 시작할 때 `git rev-parse --short HEAD`를 HANDOFF의 `리뷰 기준:` 줄에 적어 둔다. (기준을 안 주면 커밋 전이면 `git diff`, 브랜치 작업이면 `git diff main...HEAD`)
   - 스크립트가 변경분 + 변경된 파일 전체 + 그 파일을 import·호출하는 주요 파일을 `docs/review_input.txt`(커밋 안 함)로 묶고, 같은 질문(버그·보안·예외 처리 누락·성능만, 심각도·파일명·줄 번호·이유·수정 제안, 불확실하면 '추정')으로 보낸다. **`.env`·키 파일·`samples/`는 스크립트가 빼고 보낸다.**
   - Codex는 빈 임시 폴더에서 **읽기 전용**(파일을 못 고치는 모드)으로 돈다. Gemini도 빈 임시 폴더에서 보낸 내용만 본다.
   - 앱 코드가 OpenAI(Codex)·Google(Gemini) 서비스로 보내진다. 안전장치가 막으면 사용자에게 `! bash .claude/skills/build-app/cross-review.sh …` 실행을 부탁한다.
   - **도구가 없거나 로그인이 안 돼 있으면 스크립트가 실패한다 → 대신하지 말고 사장에게 설치·로그인을 부탁한다**(`!` 한 줄씩. 키는 대화창에 붙여 넣지 말라고 안내). 될 때까지 그 단계는 끝나지 않는다(HANDOFF에 "현재 단계: 5 (교차 리뷰 대기)").
     - Codex: `npm install -g @openai/codex` → `codex login`(브라우저에서 ChatGPT 계정 로그인)
     - Gemini: `winget install --id OpenJS.NodeJS.LTS -e` → `npm install -g @google/gemini-cli` → https://aistudio.google.com/apikey 에서 무료 키를 만들어 사장이 PowerShell에서 `[Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "<키>", "User")`. Google 계정 로그인 방식은 개인 무료 사용이 막혀 안 됨. 무료 키는 pro 모델을 못 써서 flash가 기본(`GEMINI_MODEL`로 바꿈)
2. **판단 규칙** (Codex·Gemini 같음):
   - 각 지적이 실제로 맞는지 **코드를 직접 확인**해서 맞는 것만 고친다. 고치기 전에 회귀 테스트 먼저(`tests/test_review_fixes.*`), 고치기는 5회 루프("구현 루프" 6번).
   - **두 곳 이상(qa-reviewer·Codex·Gemini)이 같은 문제를 지적하면 우선순위를 올린다.**
   - **심각도 '높음'인데 판단이 애매한 것은 고치지 않는다.** 구현~QA 보고 사이에는 묻지 않으므로 `docs/ask-later.md`에 근거·추천을 적고 ok-qa 보고에 "사장 확인 필요"로 올린다.
   - 각 결과 파일(`review.md`·`review_codex.md`·`review_result.md`, ug는 `ui-check.md`) 맨 아래 `## Claude 판단` 절에 지적마다 한 줄: `- [맞음] <지적> — 해결: <앱 폴더 기준 파일>:<줄> — 담당: bf|bb|ui` (아직이면 `해결: 아직`) / `- [틀림] <지적> — 이유: …`. `공격:`·`기획 누락:` 항목도 같은 방식으로 판단한다(기획 누락은 담당 bf|bb, 기획서가 틀렸으면 ask-later). 완성도 점수(sc)가 이 줄을 읽고, 해결 줄이 실제로 있어야 ✓로 센다(graph.md "파일 형식").
3. **마무리**: 고친 뒤 테스트를 다시 돌려 깨진 게 없는지 확인한다. **리뷰는 1라운드만.** 고친 코드를 다시 Codex·Gemini에 돌리지 않는다. 6단계 QA 보고에 `Codex: 반영 N / 미반영 N(이유) · Gemini: 반영 N / 미반영 N(이유) · 사장 확인 필요` 한 줄로 정리한다.

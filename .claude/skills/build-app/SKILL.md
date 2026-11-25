---
name: build-app
description: Use when the user asks to build a new app or program in this repository ("~ 앱 만들어 줘", "/build-app"), to add features to an existing app under apps/ ("~ 추가해 줘"), or to resume an app that is partway through (apps/<앱>/HANDOFF.md exists with unfinished steps).
---

# build-app — 앱 하나를 한 바퀴 만들기

## 핵심
- 사장은 **★에서만** 결정한다(OK 또는 수정 지시). **모든 팀 결과물은 ★ 검토를 받는다. 예외 없다.** 팀 안의 일(코드·테스트·고치기·내부 리뷰·커밋)은 묻지 않는다. 팀 경계는 `docs/org.md`, 팀별 기술·검토 지점은 CLAUDE.md 표.
- **급하다는 말은 만드는 양을 줄이는 이유이지 단계를 건너뛸 이유가 아니다.** 짧게는 되고, 빼기는 안 된다.
- 보안·화면·테스트 세부 규칙은 `.claude/rules/`(해당 파일을 열면 자동으로 불러짐).

## 흐름 = 그래프 (`graph.md`, 상태 `apps/<앱>/state.json`)
- **순서·실패 시 돌아갈 곳·통과 조건의 정답은 `graph.md`.** 상태는 `graph.sh`만 쓴다(직접 고치면 훅이 막음): `bash .claude/skills/build-app/graph.sh <명령> apps/<앱> …` (명령 목록: 인자 없이 실행).
- **graph.md를 통째로 읽지 않는다.** `graph.sh status apps/<앱> --short`가 현재 노드·다음·통과 조건을 한 줄로 준다. 실패 엣지·파일 형식·점수 규칙이 필요할 때만 그 절을 `grep -n`으로 찾아 읽는다.
- **자동 진행**: ★가 아닌 노드는 통과 조건을 채우면 `pass` → 묻지 않고 다음으로. 동시 노드(ui ∥ dd)는 서브에이전트로 함께.
- **자동 되돌아가기**: 테스트·리뷰·Codex·Gemini·레드팀·점수·사장 "아직이에요"에서 실패하면 graph.md 실패 엣지대로 `fail` → 담당 노드만 다시.
- **멈추는 곳은 다섯 가지뿐**: ① ★ 질문 ② 횟수 초과·정체 보고 ③ 도구 없음 ④ 탐색 사용량 2배 초과 ⑤ 안전장치가 막은 외부 공개·재잠금. "다음 단계 진행할까요?"는 묻지 않는다. **구현 시작(bb·bf)부터 ok-qa까지는 질문·보고 없음** — 애매한 것은 `docs/ask-later.md`에 모아 QA 보고 때 한 번에.
- **사장은 명령을 치지 않는다.** 첫 테스트 잠금은 tc 통과 때 자동(`auto-lock.sh`), 구현은 Stop 훅 자동 루프, 올리기는 Claude가 실행. ⑤만 한 줄을 부탁한다.

## 시작할 때
1. `git pull` → 루트 `HANDOFF.md`.
2. `state.json`이 있으면 `graph.sh status apps/<앱> --short`의 현재 노드부터(대화에 의존하지 않음, 끝난 노드는 다시 묻지 않음). `docs/progress.md`가 있으면 마지막 회차의 "다음 시도"부터, `docs/spec.md`가 있으면 먼저 읽는다.
3. 새 앱: `apps/<앱이름>/`(영문 소문자-하이픈)·`docs/`·`tests/` → `graph.sh init apps/<앱>` → req. 그래프 이전 앱(HANDOFF만): `graph.sh migrate` → "확인 필요" 노드는 ★ 질문(보기 + 추천)으로 물어 `graph.sh confirm`.
4. **기능 추가**도 그래프 한 바퀴(짧게). 문서는 `requirements.md`·`tests.md`·`design.md`에 "## N차" 절을 덧붙이고 새 테스트는 `tests/test_vN.*`. `spec.md`는 늘 지금 상태로 고친다. 앱 종류가 그대로면 설계안은 "바뀌는 설계 한두 가지 + 추천"으로 줄여도 된다.

## 단계 → 노드 → 읽을 파일
**노드에 들어갈 때 그 단계의 `ref/` 파일만 읽는다.** 각 ★ 뒤·단계 끝은 `/handoff`(state.json도 함께 커밋).

| 단계 | 노드 | 할 일 (요약) | 남길 파일 | 읽을 파일 · 쓸 스킬 |
|---|---|---|---|---|
| 1 ★ 기획 | req·ok-req·lg·ok-lg | 기획 인터뷰(성공 기준부터, 빈칸 점검표 "묻기" 0개) → 기획서 → Gemini 비판(`doc-review.sh`) → ★ → 법무 → 명세서 | `requirements.md`, `spec.md`, `legal.md` | `ref/1-plan.md` · superpowers:brainstorming |
| 2 ★ 설계 | opt·ok-opt | 설계안 3개(쉬운 것부터, 테스트 도구·설치 여부) + 점수표 + 디자인 방향 2~3개 + 사전 부검 → 사장이 고름 | `design.md`, `premortem.md` | `ref/2-design.md` · superpowers:brainstorming |
| 3 ★ 테스트 | tl·ok-tl·tc·lock | 아래 "3단계" | `tests.md`, `tests/`, `tests/.approved` | 이 파일 · superpowers:test-driven-development |
| 4 ★ 구현 | ip·ok-ip·ui∥dd·ok-ui·ok-dd·bb·cb·bf·cf | 계획 모드 → 디자인팀(DESIGN.md+시안)·백엔드팀(데이터·기능 목록) ★ → 구현 루프(bb → bf) → 단계마다 Codex 빠른 검수 | `plan.md`, `progress.md`, `NOTES.md` | `ref/4-build.md` · superpowers:writing-plans, subagent-driven-development |
| 5 리뷰 | ug·tr·qa·cx·gm | qa-reviewer → Codex `final`(+적대적) → Gemini `final`(+기획 대비), 각 1라운드, 진짜 문제만 고침 | `review.md`, `review_codex.md`, `review_result.md` | `ref/5-review.md` · superpowers:requesting-code-review |
| 6 ★ 보고 | dv·ex·rt·sa·sc·ok-qa·pub·dep | 점검·점수·레드팀 → QA 보고 → 사장 확인 → 공개 여부 | 앱·루트 `HANDOFF.md` | `ref/6-release.md` · superpowers:verification-before-completion |

앱 `HANDOFF.md`를 만들거나 `테스트 실행:`·`포트:` 줄을 고칠 때: `ref/app-handoff.md`.

**절 찾아보기** (다른 문서가 `/build-app "<절>"`로 가리키는 곳): 기획 인터뷰·견본 파일·명세서·법무 검토 → `ref/1-plan.md` / 설계안 점수표·참고 디자인 분석·사전 부검 → `ref/2-design.md` / 계획 모드·구현 루프·경영팀 → `ref/4-build.md` / 교차 리뷰 → `ref/5-review.md` / 레드팀 공격·배포 전 체크리스트·탐색·사용성 점검·사장 확인 루프·올리기·저장소 공개 여부 → `ref/6-release.md` / HANDOFF 형식 → `ref/app-handoff.md`.

### 3단계 (QA팀: 테스트 목록 → 코드 → 잠금)
- "뭐가 되면 끝인가" 목록을 쉬운 말로, **기획서 수용 기준(F1-1 …)마다 한 줄 이상** `- F1-1 → <테스트 이름> (<파일>)`. 견본 파일이 있으면 "견본 N쌍 → 정답 파일과 똑같이"를 맨 위에, 되돌리기 어려운 동작은 그 확인 절차 테스트도. graph.sh가 기획서와 대조(빠진·지어낸 번호 거부) → ★ 승인.
- 승인 뒤 테스트 코드(목록은 Playwright, 까다로운 계산·날짜는 부품 단위 추가) → tc `pass` 때 graph.sh가 `auto-lock.sh`로 **처음 한 번 자동 잠금**(ok-tl 승인 기록이 있을 때만) → `tests/.approved` 확인. 다시 잠그기는 사장만(⑤).
- **3단계 끝에는 커밋하지 않는다**(테스트만 쓴 상태는 전부 실패 = 정상). 4단계 통과 뒤 함께 커밋하고, 그 사이 상태는 HANDOFF에. 그 사이 다른 컴퓨터로 옮겨야 하면 `/handoff` "다른 컴퓨터로 옮길 때"(`wip/<앱>`). `테스트 실행:` 줄을 지우는 식의 우회는 하지 않는다.

## ★ 검토 요청 틀 (모든 ★ 노드, 한 화면 안에)
1. **결정할 것** 한 줄 2. **한눈 요약** 불릿 5개 이하 3. **볼 것**: 그림(Mermaid·시안 캡처) 또는 문서 링크 4. **추천과 이유** 한두 줄 5. **위험** 1~2개(사전 부검·Gemini 비판) 6. "OK 또는 고칠 점을 말씀해 주세요" — AskUserQuestion(추천이 첫 보기).
★에서는 OK 전에 그 결과물로 다음 일을 시작하지 않는다. 코드는 3단계 승인 뒤에만 쓴다.

## 스킬 사용 표 (말하지 않아도 그 시점에 반드시 부른다)
없으면 건너뛰지 말고 `junyeop3407/claude-setup` 설치 스크립트 실행을 부탁한다. superpowers·ECC와 순서가 겹치면 이 스킬 절차가 우선. ECC는 아래 것만(계획·TDD 명령은 안 씀, ECC 훅은 꺼 둠).

| 언제 | 스킬 |
|---|---|
| 1 기획 조사 | agent-reach(비슷한 서비스·반응, 읽기만), ecc:market-research(경쟁 3~5곳 표 → 기획서 "비슷한 서비스") |
| 2 디자인 방향 | awesome-design(서비스 이름이 나오면) |
| 4 디자인팀 시안·DESIGN.md / 다듬기 | hallmark, frontend-design / emil-design-eng |
| 모든 코드 작성·수정 | ponytail(필요한 만큼, 검증·보안·예외 처리는 빼지 않음) |
| 백엔드 코드 | ecc:springboot-patterns, ecc:springboot-security, ecc:java-coding-standards — 설계는 `rules/backend-solid.md`, 버전별 API는 context7이 우선 |
| 테스트 코드(3·4) | ecc:e2e-testing, ecc:react-testing |
| 빌드가 안 될 때 | `ecc:java-build-resolver`·`ecc:react-build-resolver` 에이전트 → 고친 뒤 `test-runner` |
| 화면 코드 전(매번) / 이어 하는 앱 4단계 전 | modern-web-guidance(iOS Safari Baseline) / 같은 것으로 옛 코드 점검 → `plan.md` |
| 라이브러리 코드·설치·버전 올릴 때(매번) | context7 — **그 앱에 깔린 버전** 문서. 기억으로 API를 쓰지 않는다 |
| 화면 완성 후 6단계 전 | web-design-guidelines, break-ui |
| 6단계 레드팀 전(화면) | chrome-devtools-mcp(localhost만) |
| QA 브라우저 테스트 | webapp-testing |
| 5 리뷰 | code-review, `ecc:react-reviewer`·`ecc:java-reviewer` |
| 6 공개 전 | security-audit |
| 각 단계 끝 | /handoff |

## 에이전트 (출력이 긴 일은 맡기고 요약만 받는다)
`test-runner`(테스트마다, N/N + 실패 한 줄) · `qa-reviewer`(5 ①) · `red-team`(6) · `backend-dev`(bb) · `frontend-dev`(bf) · `legal`(lg·sa) · `manager`(요구사항 변경 전 필수·막힘 보고 ② 전·잠금 지연). 맡긴 구현 결과는 **`test-runner`로 다시 돌리고** 승인된 테스트가 안 바뀌었는지 확인한다(훅 `check-approved.sh`도 비교).

## 지켜야 할 것
- **승인된 테스트는 고치거나 지우지 않는다.** 코드를 테스트에 맞추고 의견은 질문으로. 화면 구조가 바뀌어 요소를 못 찾으면 **검사 내용·숫자는 그대로, 찾는 위치만** 바꾸겠다고 보여 주고 다시 승인받은 뒤 고친다.
- 테스트 준비 코드(`conftest.py`·기다리는 시간·테스트 서버)는 고칠 수 있다(이유는 `NOTES.md`). 바뀐 준비 코드는 qa가 diff를 본다 — `docs/review.md` `## 준비 코드 변경`에 파일마다 한 줄이 없으면 graph.sh가 qa를 거부한다.
- **테스트 환경 탓인 실패를 앱 코드로 우회하지 않는다.** 에이전트 결과에 "우회·workaround"가 보이면 원인이 앱인지 테스트 환경인지 먼저 따진다.
- 리뷰·레드팀 지적은 고치기 전에 **회귀 테스트를 먼저**(`tests/test_review_fixes.*`, 승인 목록과 섞지 않음).
- **리뷰(5단계) 없이 "완성"이라 말하지 않는다.** 리뷰엔 사장이 필요 없으니 자리를 비워도 돌린다. 정말 못 하면 "테스트 통과, 리뷰 남음" + HANDOFF "현재 단계: 5".
- 실패한 테스트가 있으면 커밋하지 않는다(남은 실패는 `NOTES.md`). "커밋"은 늘 커밋 + 푸시.
- 테스트 하나를 3번 고쳐도 안 되면 superpowers:systematic-debugging, 그래도 안 되면 사장 보고.
- **`tests/.approved`는 직접이든 간접이든 Claude가 쓰지 않는다.** 다시 잠그기는 사장에게 `! bash .claude/hooks/approve-tests.sh apps/<앱>`(⑤).
- 추측하지 않는다. 애매하면 AskUserQuestion(보기 + 추천). spec.md는 바뀔 때마다 고친다.
- 기술은 CLAUDE.md "팀별 기본 기술". 세부는 초보가 실행하기 쉬운 쪽. 경로는 저장소 기준 상대 경로만.
- 루트 `HANDOFF.md`는 앱을 끝냈을 때와 중간에 멈출 때 갱신. 대화가 길어지면 HANDOFF·커밋 뒤 새 세션에서 "/build-app 이어서"를 제안한다.

## 흔한 실수 (핑계 → 실제)
- 급하니 질문·plan.md·계획 모드 생략 → 질문은 보기로 줄이고, plan은 3줄이라도, 계획 모드 승인은 받는다.
- 도구가 없으니 교차 리뷰 생략 / Codex·Gemini 중 하나만 / security-audit·리뷰를 했으니 레드팀 생략 → 전부 필수(리뷰는 코드 읽기, 레드팀은 실행 중인 앱 공격). 설치·로그인을 부탁하고 기다린다.
- 리뷰 "높음"이니 일단 고침 / 고쳤으니 한 번 더 리뷰 → 코드로 확인, 애매하면 ask-later. 리뷰는 1라운드.
- 될 때까지 계속 돌림 → 15회·같은 실패 3연속·점수 5바퀴·2바퀴 정체면 graph.sh가 사장 보고로 바꾼다.
- state.json을 손봄 → graph.sh로만. 깨졌으면 사장에게 알린다.
- 고쳤으니 "완료" → "해결됐어요"를 받은 뒤에만.
- approve-tests.sh를 내가 돌림 → 첫 잠금은 auto-lock, 다시 잠그기는 사장만.
- 에이전트가 통과했다고 함 → 직접 다시 돌리고 승인 테스트 해시 확인.
- 디자인·데이터 목록은 사소하니 검토 생략 → 모든 팀 결과물은 ★.
- 실제 엑셀을 테스트에 씀 → `samples/`(커밋 안 함), 테스트엔 가짜 견본 `tests/fixtures/`.
- "토스 느낌"이니 그대로 옮김 → 참고 디자인 분석 표의 "유지할 것"만.

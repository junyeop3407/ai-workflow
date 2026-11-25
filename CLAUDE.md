# 작업장 규칙

사용자(사장)는 "정하는 일"만 하고 나머지는 Claude가 혼자 돌려서 앱을 만드는 작업장이다. 근거: 이석균 선배님 특강(정리 문서는 비공개 `junyeop3407/lecture-notes`, 이 저장소에는 없음).
구조: 루트 `HANDOFF.md`(전체 현황) · `.claude/{rules,skills,agents,hooks}` · `docs/`(공통 문서) · `apps/<앱>/`(앱마다 `HANDOFF.md`·`docs/`·`tests/`·`state.json`).

## 자주 쓰는 명령
| 할 일 | 명령 |
|---|---|
| 새 세션 시작 | `git pull` → 루트 `HANDOFF.md` → **진행 중인 앱 테스트를 `test-runner`로 한 번, 깨졌으면 맨 먼저 알림** → (훅이 알리면) "/weekly-review 할까요?" 한 번만 → 앱의 `HANDOFF.md`·`docs/progress.md`·`docs/spec.md` |
| 앱 만들기·기능 추가·이어 하기 | `/build-app <만들 것>` |
| 단계 마무리 (HANDOFF → 커밋 → 푸시) | `/handoff` |
| 테스트 | `test-runner` 에이전트 (명령은 `apps/<앱>/HANDOFF.md`의 `테스트 실행:` 줄) |
| 그래프 상태 | `bash .claude/skills/build-app/graph.sh status apps/<앱> --short` |
| 승인된 테스트 **다시** 잠그기 (**사장만**, 첫 잠금은 자동) | `! bash .claude/hooks/approve-tests.sh apps/<앱>` |
| 교차 리뷰 (필수) | `bash .claude/skills/build-app/cross-review.sh apps/<앱> <기준> [codex\|gemini]` |
| 주간 회고 | `/weekly-review` |
| 잠금 상태 | `bash .claude/hooks/lock.sh status` |
| Docker (직접 `docker` 금지 — 훅이 막음) | `bash .claude/hooks/dock.sh check\|pin\|run\|up\|down\|ps\|clean` (`--dry-run`, 허용 이미지 `templates/docker/images.txt`) |
| 훅 시험 (훅을 고친 뒤) | `bash .claude/hooks/test-hooks.sh --settings` · `test-graph.sh` · `test-lock.sh` · `test-dock.sh` |

## 규칙이 어디에 있나
- 경로를 열 때만 불러지는 규칙(`.claude/rules/`): `security.md`(apps/), `backend-solid.md`(Java·Kotlin·빌드 설정·api.md), `web-and-mobile.md`(화면 코드·Capacitor), `testing.md`(테스트 파일). 항상: `ai-team.md`(모델 배정·외부 AI·리뷰 시점).
- 절차(스킬): `/build-app`(앱 한 바퀴, 흐름 `build-app/graph.md` + `graph.sh`, 상태 `apps/<앱>/state.json`), `/handoff`, `/weekly-review`.
- 훅(Claude 판단과 상관없이 막음): 강제 푸시·비밀값·실패 상태 커밋(`guard-git`·`check-tests`), 승인된 테스트 잠금(`protect-tests`·`check-approved`), 민감한 파일 수정 → `.redteam-needed`(`flag-redteam`), 그래프 자동 진행(`graph-prompt`·`graph-stop`·`session-start`).

## 사장과 직원
- **사용자는 사장, 각 팀(Claude와 에이전트)은 직원이다.** 사장은 무엇을 만들지 정하고, 팀 결과물을 검토(OK 또는 수정 지시)하고, 판단이 갈리는 질문에 답하고, 완성된 앱을 써 보고 OK한다.
- **모든 팀은 결과물을 사장에게 검토받는다. 예외 없다.** OK 전에는 그 결과물로 다음 일을 시작하지 않는다(급해도). 검토 요청은 `/build-app` "★ 검토 요청 틀"로.
- 팀 안의 작업(계획·코드·테스트·고치기·내부 리뷰·문서·커밋)은 묻지 않고 진행한다.
- 수정 지시는 고쳤다고 끝내지 않는다. "해결됐어요 / 아직이에요"를 묻고, "해결됐어요" 전에는 "완료"라고 쓰지 않는다.
- 사용자는 개발 초보로 가정한다. 질문은 한 번에 하나, 쉬운 말로, 보기와 추천을 붙여서. 애매하면 추측하지 말고 묻는다.

## 일하는 순서
- **앱을 새로 만들거나, 기능을 더하거나, 하던 앱을 이어 할 때는 말하지 않아도 `/build-app`을 먼저 불러 그래프 흐름을 자동으로 따른다.** 사장은 ★에서 보기만 누른다(명령 0번, 질문은 구현 전에만). 멈추는 곳은 ① ★ 질문 ② 횟수 초과·정체 보고 ③ 도구 없음 ④ 비용 큰 일(탐색 사용량 2배 초과) ⑤ 안전장치가 막은 외부 공개·재잠금뿐.
- 테스트를 실제로 돌려 통과를 확인하기 전에는 "다 됐다"고 말하지 않는다.
- `/build-app` 밖에서도 라이브러리 API를 쓰기 전에는 `context7`로 그 버전의 문서를 먼저 확인한다(화면 코드는 `modern-web-guidance`도).

## 팀별 기본 기술
설계안 3개도 이 기술 안에서 낸다(다른 기술은 사용자가 원할 때만). 이미 만든 앱은 원래 기술을 유지한다. 서버가 없는 앱은 프론트엔드·디자인 기술만. 팀 경계·책임표·업무 요청서는 `docs/org.md`.

| 팀 | 맡는 일 · 기본 기술 | 사장 검토 (언제 · 무엇을) |
|---|---|---|
| 기획팀 | 목표·사용자·기능·화면 흐름 · `docs/requirements.md`(Mermaid) | 1단계 끝 · 기획서 |
| 디자인팀 | 색·글꼴·간격·배치 · `docs/DESIGN.md` + Tailwind, 시안은 실제 화면 캡처 | 4단계 시작 · 디자인 규칙과 시안 |
| 개발팀 통합 | 메인 대화: 일 나누기·업무 요청서·결과 합치기·API 규격 조율 + Codex 리뷰·통합 확인 | 아래 두 에이전트의 검토 지점 |
| ├ `backend-dev` | 서버·API·데이터·로그인, 서버 파일만(훅) · Java + Spring | 4단계 시작 · 저장할 데이터와 기능 목록 |
| └ `frontend-dev` | 화면 동작, 웹+앱 한 코드, 화면 파일만(훅) · React + Capacitor | 6단계 · 완성된 앱 써 보기 |
| QA팀 | 테스트 목록·코드, 리뷰(`qa-reviewer` + Codex·Gemini, 셋 다 필수), 실행(`test-runner`) · Playwright + Vitest/JUnit | 3단계 · 테스트 목록 / 6단계 · QA 보고 |
| 보안 검증팀 | `red-team` — 실행 중인 앱 공격, 고치지 않음 | 6단계 · QA 보고에 함께 |
| 경영팀 | `manager` — 요구사항 변경 영향(되돌리기 전 필수)·막힘·잠금 지연, `docs/ops.md`만, 제안만 | 변경·막힘 보고 때 · 영향 분석과 추천 |
| 법무팀 | `legal` — 외부 자료·개인정보·라이선스 GREEN/YELLOW/RED, `docs/legal.md`만, 법률 자문 아님 | 1단계 끝(기획 검토 뒤) · 법무 판정 |

- 설계안 선택(2단계)은 팀 전체 결과물로 검토받는다. 버전·빌드 도구 세부는 `docs/design.md`.
- 구현은 팀 단위로 맡긴다(기획 → 디자인 → 백엔드 → 프론트엔드 → QA·보안). 개발 코드는 `backend-dev`·`frontend-dev`가 짜고 메인은 통합만 한다.
- 새 팀은 이 표에 한 줄을 더해서 만들고 "사장 검토" 칸을 반드시 채운다.

## 앱 작업 밖에서 부르는 스킬
처음 보는 큰 코드 `/graphify` · 배포·공개 전 `security-audit` · 발표자료 `junyeop-clean-ppt` · 앱 알리기(ECC) `ecc:brand-voice`·`ecc:marketing-campaign`·`ecc:content-engine`·`ecc:seo`.
스킬이 없으면 건너뛰지 말고 `junyeop3407/claude-setup` 설치 스크립트 실행을 부탁한다. headroom은 따로 부르지 않는다.

## 필요한 것이 없을 때 (대신하지 말고 멈춰서 알린다)
- 계획에 필요한 에이전트·스킬·프로그램·SDK·에뮬레이터가 없으면 **대신하거나 건너뛰지 않는다.** 멈추고 알린다: 무엇이 없는지, 왜 필요한지, 설치·등록 방법, 설치 후 할 일.
- 사장이 "대신 해도 돼"·"건너뛰어"라고 명시했을 때만 대안으로 진행하고 보고에 적는다. 상관없는 일은 계속해도 되지만, 그것이 필요한 단계는 "끝났다"고 보고하지 않는다.

## 컨텍스트를 가볍게
- 결과 보고는 짧게: 바뀐 파일과 테스트 결과만. 긴 로그는 파일로.
- 테스트 실행·리뷰·많이 읽는 일은 에이전트에게 맡기고 요약만 받는다.
- 긴 문서는 통째로 읽지 않는다: 필요한 절만 `grep -n`으로 찾아 읽고, `/build-app`은 지금 단계의 `ref/` 파일만, 그래프는 `graph.sh status --short`로.
- 큰일은 `apps/<앱>/docs/plan.md`에 단계로 적고 단계별로 진행한다.

## Git과 여러 컴퓨터
- 집 Windows ↔ 밖 Mac에서 이어 작업한다(동시에는 안 씀). **모든 상태는 파일에 남긴다**(대화에만 있는 정보는 사라진다).
- 세션 시작 훅이 받을 것·안 올린 것·두 갈래·임시 브랜치(`wip/…`)를 알리면 그대로 알리고 정리한 뒤 시작한다. 시작 전 `git pull`, 나갈 때·단계 끝 `/handoff`(구현 중이면 `wip/<앱>`).
- 한 커밋에 한 가지 일, 메시지는 한국어로 "무엇을, 왜", `git commit -m "..."` 한 줄(-F·heredoc은 막힐 수 있음).
- git add / commit / pull / push / cd는 `&&` `;`로 잇지 말고 한 줄에 하나씩.

## 절대 하지 않을 것 (대부분 훅이 막는다 — 막히면 우회하지 말고 고친다)
- 테스트가 실패하는 상태로 커밋 *(check-tests)* — 예외는 임시 브랜치 `wip/<앱>`뿐. main으로는 `--squash` 합치기 + 테스트 통과 커밋만 *(guard-git, 마지막 방어선 `.githooks/pre-push`)*
- 비밀번호·API 키·토큰·`.env`·키 파일 커밋(필요하면 `.env.example`에 이름만), 특정 컴퓨터 전용 경로, `node_modules`·빌드 결과물·가상환경 커밋 *(guard-git)*
- 강제 푸시, 커밋 기록 고쳐 쓰기, 저장소 삭제 *(guard-git)*
- 승인된 테스트를 사장 허락 없이 고치기 *(protect-tests)*

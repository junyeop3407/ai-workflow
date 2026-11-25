# HANDOFF — 다음 세션 시작 가이드

마지막 갱신: 2026-11-25 (토큰 최적화: 규칙·문서·스킬을 짧게, 자세한 기록은 docs/history.md로 — 다음은 Docker 2단계(사장 설치) 또는 첫 앱)
마지막 작업 컴퓨터: Windows 2026-11-24 (main)

## 1. 한 줄 요약
이석균 선배님 특강(AI 기초) 방식으로 앱을 만드는 **작업장 견본**. 사장(사용자)은 ★에서만 정하고, 팀(기획·디자인·개발(백엔드·프론트엔드 에이전트)·QA·보안 검증·법무·경영, `docs/org.md`)이 그래프(`build-app/graph.md`)를 따라 자동으로 돈다. 규칙·스킬·훅·그래프는 준비됐고 아직 만든 앱은 없다. **다음 할 일: 첫 앱 만들기 (`/build-app 만들고 싶은 것`).**

## 2. 새 세션 시작
- 이 폴더에서 `claude` 실행 → 첫 마디 **"HANDOFF.md 읽고 이어서 해 줘"**, 새 앱은 **`/build-app 만들고 싶은 것`**. 다른 컴퓨터면 `git pull` 먼저.
- **집 Windows ↔ 밖 Mac (동시에는 안 씀)**: 열 때 세션 시작 점검이 받을 커밋·안 올린 커밋·두 갈래·임시 브랜치(`wip/<앱>`)·커밋 안 한 변경·지난번 컴퓨터를 알린다. 나갈 때 "마무리해 줘"(`/handoff`) — 테스트 통과면 main, 구현 중이면 `wip/<앱>`.
- 따라오지 않는 것(컴퓨터마다): `node_modules`·빌드 결과물, `.env` 비밀값, `samples/`, Codex·Gemini·context7 로그인, `GEMINI_API_KEY`. iOS 빌드는 Mac만.
- 처음 쓰는 컴퓨터: `docs/setup.md`.

## 3. 로드맵 (자세한 기록: `docs/history.md`)
| 단계 | 상태 |
|---|---|
| 구조·규칙·`/build-app`·훅·교차 리뷰(Codex+Gemini)·견본 파일·설계 점수표·최신 웹 표준·MCP 2개·출시 전 점검·ECC·품질 점검·루프 다섯 칸 | ✅ ~2026-11-20 |
| 그래프(노드 32·실패 엣지·멈추는 곳 다섯·완성도 90%) + 검증 고침 | ✅ 2026-11-20 |
| 백엔드 SOLID(ArchUnit) · 앞단계 보완(기획 인터뷰·사전 부검·★ 검토 틀) | ✅ 2026-11-22 |
| 조직 개편 ①개발팀 에이전트 ②법무 ③잠금 도구 ④경영 · 두 컴퓨터(wip 브랜치·pre-push) · Docker 1단계 | ✅ 2026-11-23 |
| Docker 1단계 보안 보강 · GitHub main 보호(강제 푸시·삭제 금지) | ✅ 2026-11-24 |
| 토큰 최적화: CLAUDE.md·ai-team·HANDOFF 줄임, `/build-app`을 핵심 + 단계별 `ref/`로 나눔, graph.sh status 요약, 테스트 실패 발췌 | ✅ 2026-11-25 |
| Docker 2단계: 사장이 Windows·Mac에 Docker Desktop 설치 → `dock.sh check` → `pin` → images.txt 커밋 → 견본 compose로 `up` 한 번(yaml_flat이 실제 `compose config` 출력을 읽는지 확인) | ⬜ 사장 설치 뒤 |
| 첫 앱으로 새 조직 흐름 한 바퀴 | ⬜ 다음 |

## 4. 정해진 것 (다시 묻지 않기)
- 저장소 하나에 앱 여러 개(`apps/<앱이름>/`). 스킬·훅은 저장소 안 `.claude/`(다른 컴퓨터로 따라가게).
- 사용자는 개발 초보 — 질문은 쉽게, 하나씩, 보기와 추천. 팀별 기술·검토 지점은 CLAUDE.md 표.

## 5. 주의할 점
- 공개 주소 올리기가 안전장치에 막히면 사장이 `! bash apps/<앱>/deploy.sh` 같은 짧은 한 줄을 실행(`!` 앞 띄어쓰기 금지).
- 훅은 앱 HANDOFF의 `테스트 실행:` 줄을 돌린다(허용 명령은 `build-app/ref/app-handoff.md`). 파이썬 테스트는 `bash tests/run.sh`(견본 `templates/run.sh`).
- 구현 중(테스트 일부 실패) Stop 훅이 응답을 한 번 멈춰 세우는 것은 정상. 자동 루프가 사용량 한도에 걸려 멈춰도 고장이 아니다 — state.json에서 이어 간다.
- 새 규칙 넣을 곳: 매번 알아야 함 → CLAUDE.md(짧게), 한 경로 → `.claude/rules/`(`paths:`), 절차 → 스킬(단계별은 `build-app/ref/`), 절대 규칙 → 훅, 출력이 긴 일 → 에이전트, 지난 기록 → `docs/history.md`.
- 훅은 jq 없이 grep/sed로 동작(Windows Git Bash). 훅을 고치면 `test-hooks.sh --settings`로 다시 확인. 시험은 Windows에서 오래 걸림(`test-graph.sh` 약 10분, `test-hooks.sh` 약 3분). Mac에서는 아직 시험을 실제로 돌려 본 적 없음.
- 승인 단어(approve-tests·.approved)가 든 Bash 명령은 막힌다(읽기·`git add <경로>`·`git commit -m`은 통과). 그 단어가 든 문서 수정은 sed 말고 Edit로.
- graph-stop의 "★ 대기 중 코드가 바뀜" 알림은 수정 시각 비교라 git pull 직후 한 번 멈출 수 있다(사장 결정으로 유지).
- 실제 엑셀·CSV는 `apps/<앱>/samples/`(커밋 안 함), 테스트엔 가짜 견본 `tests/fixtures/`. 그 밖의 엑셀·CSV·hwp는 guard-git이 막는다.
- ECC 플러그인은 Node.js가 필요하다(훅을 꺼 둬도 시작 검사가 node로 돈다).

# HANDOFF — 다음 세션 시작 가이드

마지막 갱신: 2026-11-23 (조직 개편 ① 개발팀 = 진짜 팀 에이전트)

## 1. 한 줄 요약
이석균 선배님 특강(AI 기초)의 방식대로 앱을 만드는 **작업장 견본**이다. 사용자는 **사장**, Claude의 팀들(기획·디자인·프론트엔드·백엔드·QA)은 **직원**이고, 모든 팀의 결과물은 사장 검토를 받는다. 규칙, `/build-app` 스킬, 교차 리뷰, 훅, **그래프(앱 작업이 graph.md 흐름을 따라 자동으로 흐름, 사장은 ★에서 보기만 누름)** 가 준비되어 있고 아직 만든 앱은 없다. **다음 할 일: 첫 앱 만들기 (`/build-app 만들고 싶은 것`).**

## 2. 새 세션 시작 방법
- 인텔리제이(또는 터미널)에서 이 폴더를 열고 `claude` 실행
- 첫 마디: **"HANDOFF.md 읽고 이어서 해 줘"**, 새 앱은 **`/build-app 만들고 싶은 것`**
- 다른 컴퓨터: `git pull` 먼저

## 3. 처음 쓰는 컴퓨터 준비 (한 번만)
1. git 설치 (Windows는 Git Bash가 함께 깔림. 훅이 bash로 돈다)
2. GitHub CLI: `winget install GitHub.cli` → `gh auth login --web` → `gh auth setup-git`
3. 저장소 받기: `git clone <이 저장소 주소>`
4. 이 폴더를 Claude Code로 처음 열면 superpowers·modern-web-guidance·context7·chrome-devtools-mcp·ecc 플러그인 설치를 묻는다 → 모두 "예" (ecc는 개인 개발자 affaan-m의 공개 플러그인. 이 저장소 설정이 공식 저장소 `affaan-m/ECC`에서만 받게 되어 있다) (chrome-devtools는 Chrome 브라우저가 깔려 있어야 함)
   - context7은 처음 한 번 로그인해야 쓸 수 있다: `/mcp` → context7 → Authenticate → 열리는 브라우저에서 로그인. `claude mcp list`에 context7이 `Needs authentication`으로 나오면 아직 안 한 것
5. git 이름·이메일이 없으면: `git config user.name "이름"`, `git config user.email "메일"`
6. 팀 기본 기술 도구 (첫 앱을 만들 때 Claude가 필요한 것만 설치를 안내한다):
   - Java (백엔드팀): `winget install --id EclipseAdoptium.Temurin.21.JDK -e` (Mac `brew install --cask temurin@21`)
   - Node.js (프론트엔드팀·디자인팀·QA팀의 React, Vite, Tailwind, Playwright, Vitest): `winget install --id OpenJS.NodeJS.LTS -e` (Mac `brew install node`)
   - Playwright 브라우저 (QA팀, 앱 폴더에서 한 번): `npx playwright install chromium webkit` (webkit은 Safari 엔진, 호환성 테스트용)
   - 파이썬으로 테스트하는 앱일 때만: `py -m pip install pytest playwright` → `py -m playwright install chromium` (Mac은 `python3`)

## 4. 로드맵
| 단계 | 내용 | 상태 |
|---|---|---|
| 0~3 | 폴더 구조, 규칙(CLAUDE.md), `/build-app` 스킬, 훅 | ✅ 준비됨 |
| 그래프 | `build-app/graph.md`(노드 32·실패 엣지·멈추는 곳 다섯·체크리스트 20 대응) + `apps/<앱>/state.json` + `graph.sh`(순서 강제) + 훅(SessionStart·UserPromptSubmit·Stop 자동 루프·state 직접 편집 막기). 사장 명령 0번(첫 잠금 자동 `auto-lock.sh`, /goal 대신 Stop 훅 자동 루프, 올리기는 Claude가 실행), 구현~QA 보고 사이 질문 0번(`ask-later.md`), 완성도 90%(필수 관문 + 점수, `graph.sh score`), bb(백엔드: JUnit + api.md 예시 `api-check.sh`, `templates/backend.sh`) → bf 순서. 시험 `test-graph.sh` 59개·`test-hooks.sh --settings` 129개 | ✅ 2026-11-20 |
| 그래프 검증 고침 | ① 테스트 개수 확인: bf·tr·sc가 exit 0만 믿지 않고 출력에서 개수를 읽어 통과 ≥ 승인된 테스트 수·건너뜀 0일 때만 통과, 못 읽으면 거부(`run.sh`를 `exit 0`으로 위조하는 길 차단, `graph.sh tcount`, Playwright·Vitest·Jest·pytest·Maven·Gradle·node --test). 바뀐 준비 코드(run.sh·conftest·fixtures·config)는 qa가 review.md `## 준비 코드 변경`에 파일마다 적어야 통과 ② AI 노드 "내는 것" 파일이 있고 비어 있지 않아야 pass ③ "서버 없음"·"화면 없음" 건너뛰기 연쇄 ④ pass에 표에 없는 다음 노드 → 거부. 자동 보안 리뷰 지적 3개도 고침(준비 코드 경로는 글자 그대로 비교, 점 파일·러너 설정 포함, 기준은 qa 통과 때만 남겨 첫 qa가 전부 봄). 시험 `test-graph.sh` 104개·`test-hooks.sh --settings` 129개. 남은 위험: run.sh가 합계 줄을 echo로 꾸미면 graph.sh는 못 가림(qa 준비 코드 리뷰가 잡음) | ✅ 2026-11-20 |
| 백엔드 SOLID | `.claude/rules/backend-solid.md`(원칙별 뜻·Spring 적용·위반 신호, 과한 추상화도 위반, 기준 "바깥 연결이거나 종류 2개 이상이면 인터페이스"). 확인: bb 때 QA팀이 ArchUnit `ArchitectureTest`를 JUnit에 넣어 위반 시 `./gradlew test` 실패 · cross-review.sh 요청문에 SOLID 점검 · qa-reviewer가 `[중간]`(`원칙: S/O/L/I/D/과함`) 지적. 시험 test-graph·test-hooks 통과. 사장 OK. 견본 `templates/ArchitectureTest.java`(ArchUnit 1.5.1, 규칙 6개) — context7 대신 공식 웹 문서·GitHub 소스로 확인(사장 허락). 깨끗한 견본 코드 6/6 통과, 심어 둔 위반 4개 모두 잡음 | ✅ 2026-11-22 |
| 앞단계 보완 | 분석 `docs/front-stage-review.md`(사장 레퍼런스 3개 + Anthropic·grill-me·Spec Kit·EARS·Shape Up·사전 부검). 반영 ①~⑧: 성공 기준·빈칸 점검표 인터뷰(`SKILL.md` "기획 인터뷰", 견본 `templates/requirements.md`), Gemini 기획서 비판(`doc-review.sh`, agy), 사전 부검(`docs/premortem.md`), 수용 기준 `F1-1`, graph.sh 검사 `req`·`trace`·`undecided`, 되돌리기 어려운 동작 확인 절차, ★ 검토 요청 틀. 추가 ⑨~⑬도 반영: 수용 기준마다 `— 예:` 예시, 출시 안내문 3문장 + 예상 질문, 기능 `[1차|나중·꼭|많을수록|놀람]`(1차만으로 처음부터 끝까지 한 번 돌기, 나중은 테스트·점수에서 빠짐), ★기획 검토 때 회색 상자 화면 초안(`docs/wireframe/`, 절차만) | ✅ 2026-11-22 |
| 조직 개편 ① 개발팀 | 사장의 "AI 가상오피스 조직 명세"(비서 제외)를 적용. 정한 것: Codex = 개발팀 **리뷰·통합 확인**(구현 안 함, 교차 리뷰 독립 유지), 백엔드·프론트는 **진짜 팀 에이전트** `backend-dev`·`frontend-dev`(sonnet, bb·bf에서 실제로 코드를 짬, 메인은 통합·업무 요청서·커밋). 파일 경계 훅 `team-files.sh`(Edit·Write 즉시 차단 + Bash로 쓴 것은 맡기기 직전 `mark`·받은 직후 `check`로 저장소 전체 비교, **목록에 없는 파일은 기본 거부** — 테스트·러너 설정·package.json·vite.config·`docs/`·.gitignore·state.json은 둘 다 못 고침, 경로는 저장소 기준·대소문자 무시·`//` `./` `../` 거부). 자동 보안 리뷰 지적 4개(경로 우회 2·check 범위·기본 허용) + 2차 4개(이름 바꾸기로 숨기기·기준점 파일 고쳐 쓰기 → 기준 표를 git 객체 해시로 메인이 들고 있음·Windows 특수 이름·무시 파일 내용/git 설정 비교) 반영. 조직도·책임표·업무 요청서 `docs/org.md`. 자동 루프(Stop 훅)는 메인에 그대로. 시험 test-hooks --settings 166개·test-graph 통과 | ✅ 2026-11-23 |
| 조직 개편 ② 법무·경영 | 법무팀(외부 데이터·라이선스·개인정보 GREEN/YELLOW/RED)·경영팀(요구사항 변경 영향·순서 조정)을 넣을지·어디에 넣을지 사장 결정 대기. 실제 앱으로 backend-dev·frontend-dev 흐름은 아직 안 돌려 봄 | ⬜ 다음 |
| 다음 | 첫 앱 만들기 (`apps/<앱이름>/`) | ⬜ 다음 |
| 교차 리뷰 | Codex + Gemini CLI 리뷰 (**둘 다 필수**, 변경분 1라운드, README 참고) | ✅ 준비됨 |
| 구조 정리 | CLAUDE.md를 rules·skills·hooks·agents로 나눔 (130 → 93줄) | ✅ 2026-11-01 |
| 견본 파일 | 변환 전/후 실제 파일 → 요구사항·테스트 정답 (`/build-app` "견본 파일"), 실제 데이터 파일 커밋 차단(guard-git, `samples/`) | ✅ 2026-11-13 |
| 고르기 돕기 | 2단계 설계안 점수표(가중치 4기준·추천), 참고 디자인 분석(유지할 것 / 바꿀 것 / 베끼지 말 것 → DESIGN.md "참고") | ✅ 2026-11-13 |
| 최신 웹 표준 | Chrome 팀 modern-web-guidance 플러그인 자동 설치·자동 사용(화면 코드 전 가이드 검색, iOS Safari Baseline 기준, 이어 하는 앱 현대화 점검) | ✅ 2026-11-16 |
| MCP 2개 | context7(라이브러리 버전별 최신 문서, 코드 작성 전 자동), chrome-devtools-mcp(6단계 콘솔·네트워크·성능 점검) 플러그인 자동 설치·자동 사용. playwright·github·filesystem MCP는 기존 기능(Playwright 테스트·webapp-testing, gh CLI, 기본 파일 도구)과 겹쳐서 넣지 않음 | ✅ 2026-11-16 |
| 출시 전 점검 | 결제는 PG사 결제 확인 후 주문 확정, 가입 동의 필수·선택 분리, 하단 개인정보처리방침·약관·사업자 정보, 연습용·운영 DB 분리 + 매일 백업 (security.md 5·6절, 배포 전 체크리스트 12 → 16개) | ✅ 2026-11-18 |
| ECC 플러그인 | affaan-m/ECC 자동 설치(공식 저장소만). 쓰는 것만 골라 `/build-app` 스킬 표에 넣음: 시장조사, Spring·테스트 작성 가이드, 빌드 에러 해결·언어별 리뷰 에이전트. 앱 밖: 말투·마케팅·콘텐츠·SEO. ECC 훅은 꺼 둠(이 저장소 훅과 겹치고 매 동작마다 느려짐), 계획·TDD 명령은 superpowers와 겹쳐 안 씀, ECC 규칙(rules)은 항상 읽혀 컨텍스트를 먹어서 안 넣음 | ✅ 2026-11-19 |
| 품질 점검 | Safari 엔진(webkit)·폰 화면 호환성 테스트, axe 자동 접근성 검사, 성능 기준(LCP 2.5초·CLS 0.1), 서버 앱 부하 테스트(동시 50명, localhost), 탐색·사용성 점검(선택, 예상 비용 고지 후 사장 "진행해"일 때만). 배포 전 체크리스트 16 → 20개 | ✅ 2026-11-18 |
| 루프 다섯 칸 | 목표·채점표에 더해 **일지**(`progress.md`)·**브레이크**(15회·같은 실패 3회·디버깅 후에도 안 되면 사장 보고)·**잠금**(`tests/.approved` 해시, 사장만 잠금, Bash로 고쳐도 커밋 직전·Stop에서 잡음). 4단계는 `/goal` 한 문장. 교차 리뷰 Codex+Gemini(4단계 단계별 Codex, 5단계 Claude→Codex→Gemini). "해결됐어요 / 아직이에요" 확인 루프. qa-reviewer·red-team 메모리(공개 저장소라 일반 패턴만), `/weekly-review`. 예약 작업 없이 세션 시작 때 점검. 훅 시험 `test-hooks.sh` | ✅ 2026-11-20 |

## 5. 파일 구조
```
├── CLAUDE.md                              매번 알아야 하는 사실만 (소개·명령·역할·팀 기술)
├── .claude/rules/                         주제별 규칙 (해당 경로를 열 때만 불러짐)
│   ├── security.md                        보안 (apps/**)
│   ├── web-and-mobile.md                  웹+안드로이드·iOS 화면 (화면 코드·Capacitor)
│   └── testing.md                         테스트 (tests/·테스트 파일)
├── .claude/agents/                        서브에이전트 (요약만 돌려줌)
│   ├── test-runner.md                     테스트 실행 → N/N + 실패 요약
│   ├── qa-reviewer.md                     5단계 분리 리뷰 (memory: project)
│   ├── red-team.md                        6단계 실행 중인 앱 공격 (memory: project)
│   ├── backend-dev.md                     개발팀 백엔드: bb에서 서버 코드 작성 (서버 파일만)
│   └── frontend-dev.md                    개발팀 프론트엔드: bf에서 화면 코드 작성 (화면 파일만)
├── docs/org.md                            조직도·책임표·개발팀 파일 경계·업무 요청서
├── .claude/hooks/team-files.sh            개발팀 에이전트 파일 경계 (훅 + check·owner)
├── .claude/agent-memory/                  qa-reviewer·red-team 메모리 (커밋됨, 일반 패턴만)
├── .claude/skills/weekly-review/SKILL.md  /weekly-review 주간 회고 (반복된 실수 → 규칙 후보 최대 3개)
├── docs/last-weekly-review.txt            마지막 주간 회고 날짜 (세션 시작 훅이 읽음)
├── .claude/skills/handoff/SKILL.md        /handoff 단계 마무리 (HANDOFF → 커밋 → 푸시)
├── HANDOFF.md                             이 파일 (저장소 전체 현황)
├── README.md                              이 견본을 새 프로젝트에 쓰는 방법
├── .claude/skills/build-app/SKILL.md      /build-app 절차 (앱 하나 한 바퀴, 기능 추가도 같은 순서)
├── .claude/skills/build-app/templates/    견본 파일 (파이썬으로 테스트하는 앱용 run.sh)
├── .claude/skills/build-app/cross-review.sh  교차 리뷰 (필수, Codex·Gemini CLI로 변경분 리뷰, snapshot 기준점)
├── .claude/skills/build-app/graph.md      앱 흐름(노드·실패 엣지·멈추는 곳 다섯·체크리스트·점수 규칙). graph.sh가 이 표만 읽음
├── .claude/skills/build-app/graph.sh      순서 강제·state.json 쓰기 (status/pass/fail/approve/loop/score/migrate/lint …)
├── .claude/skills/build-app/api-check.sh  api.md 예시 요청을 로컬 서버에 보내 응답 비교 (bb 노드)
├── .claude/skills/build-app/templates/backend.sh  백엔드 테스트 견본(JUnit → 서버 켜기 → api 확인 → 끄기, 안전장치)
├── .claude/hooks/graph-stop.sh            Stop: 구현 자동 루프·진행 노드 두고 멈추기 막기
├── .claude/hooks/graph-prompt.sh          UserPromptSubmit: 앱 작업이면 현재 노드 한 줄
├── .claude/hooks/guard-state.sh           state.json 직접 편집 막기
├── .claude/hooks/auto-lock.sh             첫 테스트 잠금 자동(한 번만, ok-tl 승인 기록 필요)
├── .claude/hooks/test-graph.sh            그래프 시험 + 가짜 앱 이야기 표
├── setup/new-project/SKILL.md             "새 프로젝트 만들어 줘" 개인 스킬 (README 참고해 설치)
├── .claude/hooks/check-tests.sh           테스트 실패 시 커밋·완료 보고 막기
├── .claude/hooks/guard-git.sh             강제 푸시·기록 수정·저장소 삭제 차단, 커밋 전 비밀값·.env·절대경로 검사
├── .claude/hooks/protect-tests.sh         승인 목록(.approved)의 테스트 수정 시 사장 확인 창, Claude의 승인 스크립트 실행 차단
├── .claude/hooks/approve-tests.sh         승인된 테스트 잠그기 (사장만 ! 로 실행)
├── .claude/hooks/check-approved.sh        커밋 직전·Stop에서 승인 테스트 해시 비교
├── .claude/hooks/flag-redteam.sh          민감한 파일 수정·커밋 시 .redteam-needed 표시
├── .claude/hooks/agent-memory-only.sh     검수 에이전트는 자기 메모리 폴더만 쓰게
├── .claude/hooks/session-start.sh         세션 시작 점검·주간 회고 알림 (예약 작업 대신)
├── .claude/hooks/test-hooks.sh            훅 시험 (가짜 입력으로 막힘/통과 표)
├── .claude/settings.json                  훅 등록, 플러그인 켜기(superpowers·modern-web-guidance·context7·chrome-devtools-mcp·ecc), ECC 훅 끄기
└── apps/                                  앱 하나당 폴더 하나 (아직 비어 있음)
```

## 6. 정해진 것 (다시 묻지 않기)
- 저장소 하나에 앱 여러 개 (`apps/<앱이름>/`)
- 스킬·훅은 저장소 안 `.claude/`에 둔다 (GitHub로 다른 컴퓨터에 따라가게)
- 사용자는 개발 초보. 질문은 쉽게, 하나씩, 보기와 추천을 붙여서
- 사용자는 사장, 팀은 직원. 팀별 기본 기술(백엔드 Java+Spring, 프론트엔드 React, 디자인 DESIGN.md+Tailwind, QA Playwright+Vitest/JUnit, 기획 저장소 안 기획서)과 사장 검토 지점은 `CLAUDE.md` "팀별 기본 기술" 표

## 7. 주의할 점 (앞선 시험 앱에서 배운 것, 스킬에 반영됨)
- 공개 주소에 올리기(GitHub Pages 등)는 안전장치 때문에 Claude가 직접 못 한다. 사용자가 `! bash apps/<앱>/deploy.sh` 같은 짧은 한 줄을 실행한다. `!` 앞에 띄어쓰기가 있으면 실행되지 않는다.
- 훅은 `HANDOFF.md`의 `테스트 실행:` 줄을 읽어 돌린다. 허용 명령: `npx playwright test`, `npx vitest run`, `npm test`, `./gradlew test`, `mvn test` 등(전체 목록은 스킬). 여러 도구를 함께 돌려야 하면 `tests/run.sh`에 담아 `bash tests/run.sh`.
- 파이썬으로 테스트하는 앱이면: Windows의 `python`은 가짜 실행 파일일 수 있으니 `bash tests/run.sh`(견본 `templates/run.sh`, py·python3 자동 선택).
- 구현 중(테스트 일부 실패)에는 Stop 훅이 응답을 한 번 멈춰 세운다. 정상이다.
- 새 규칙을 넣을 때: 매번 알아야 하는 사실 → CLAUDE.md(200줄 이하 유지), 한 주제·한 경로 규칙 → `.claude/rules/`(파일 위 `paths:`), 절차 → 스킬, 절대 어기면 안 되는 것 → 훅, 출력이 긴 일 → 에이전트.
- ECC 플러그인은 Node.js가 있어야 한다(훅을 꺼 둬도 시작 검사가 node로 돈다). 교차 리뷰 때문에 어차피 설치하는 것.
- 훅은 jq 없이 grep/sed로 동작한다(Windows Git Bash에 jq가 없는 경우가 많음).
- 훅을 고치면 `bash .claude/hooks/test-hooks.sh --settings`로 막힘/통과 표를 다시 확인한다.
- 승인 단어(approve-tests·.approved)가 든 Bash 명령은 막히지만, 읽기 명령·`git add <경로>`·`git commit -m "<메시지>"`는 통과한다(같은 명령에 `;` `&&` `|`로 붙은 다른 명령은 검사). 커밋 메시지는 `-m`으로 쓴다(`-F`·heredoc 메시지는 줄마다 검사돼 막힐 수 있음). 그 단어가 든 문서 수정은 sed 말고 Edit로.
- 구현은 /goal 대신 Stop 훅 자동 루프로 돈다(사장 명령 없음). 사장이 원하면 /goal을 따로 써도 된다.
- 자동 루프는 오래 혼자 돌아서 **Claude 사용량 한도에 걸려 중간에 멈출 수 있다.** 고장이 아니다 — 진행 상황은 state.json에 남고, 한도가 풀린 뒤 새 세션을 열면 SessionStart 훅이 현재 노드를 알려 이어 간다.
- 그래프 시험은 Windows에서 몇 분 걸린다(`test-graph.sh` 약 10분, `test-hooks.sh` 약 3분). graph.sh 한 번에 1~4초.
- graph-stop의 "★ 대기 중 코드가 바뀜" 알림은 수정 시각 비교라 git pull 직후 한 번 멈출 수 있다(사장 결정으로 유지, 거슬리면 내용 지문 방식으로 바꿈).
- 사장이 준 실제 엑셀·CSV 등은 `apps/<앱>/samples/`(커밋 안 함, 그 컴퓨터에만 있음). 테스트에는 칸·형식이 같은 가짜 견본을 `tests/fixtures/`에. 그 밖의 엑셀·CSV·hwp는 guard-git이 커밋을 막는다.

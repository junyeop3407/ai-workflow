---
paths:
  - "apps/*/tests/**"
  - "apps/**/*.{test,spec}.*"
  - "apps/**/playwright.config.*"
  - "apps/**/vitest.config.*"
  - "apps/*/docs/tests.md"
---

# 테스트 규칙 (QA팀)

## 도구
- 사장이 승인한 목록(`docs/tests.md`)은 Playwright(실제 브라우저를 사람처럼 조작)로.
- 계산·날짜처럼 까다로운 부분은 부품 단위 테스트를 QA팀이 알아서 더한다(React는 Vitest, Java·Spring은 JUnit). 승인 대상 아님.
- 파일을 바꿔 주는 앱은 "가짜 견본 입력 → 정답 파일과 칸 하나하나 같은지" 비교 테스트를 맨 앞에 둔다. 견본은 `tests/fixtures/`에, 실제 파일은 쓰지 않는다(`/build-app` "견본 파일" 절).
- 웹 테스트에 더해, 폰 크기 화면 캡처와 안드로이드 에뮬레이터 실행 확인을 QA 보고에 넣는다.

## 품질 점검 (QA팀이 알아서 더함, 승인 대상 아님. 결과는 QA 보고 "배포 전 체크리스트"에)
- **호환성**: `playwright.config`의 `projects`에 `chromium`, `webkit`(Safari 엔진), 폰 화면(`devices['iPhone 13']` 등)을 넣어 **같은 승인 테스트를 셋 다에서** 돌린다. iOS가 기준이라 webkit이 실패하면 통과가 아니다. 브라우저 설치: `npx playwright install chromium webkit`.
- **접근성**: `@axe-core/playwright`로 주요 화면마다 자동 검사를 하고, 심각(`serious`·`critical`) 위반이 0개여야 한다. 테스트는 `tests/a11y.spec.*`에 둔다.
- **성능** (화면이 있는 앱, 6단계 DevTools 점검에서 측정): LCP 2.5초 이하, CLS 0.1 이하, 콘솔 에러 0개. 넘으면 고치고 다시 잰다.
- **부하** (서버가 있는 앱, 6단계 레드팀 전): 로컬에서 띄운 서버의 로그인·주요 API에 `npx autocannon -c 50 -d 30 <localhost 주소>`(동시 50명, 30초). 에러 0%, 응답 99%가 1초 이하여야 한다. **localhost에만** 보낸다(외부·배포된 주소 금지). 로컬 컴퓨터 기준 참고값이라는 점을 보고에 적는다.

## 승인된 테스트는 건드리지 않는다
- 승인된 테스트는 사장 허락 없이 고치거나 지우지 않는다. 승인 목록은 `tests/.approved`(파일 경로 + sha256). **사장이 `! bash .claude/hooks/approve-tests.sh apps/<앱>`로만 만든다** — Claude는 직접·간접(새 스크립트, 이름 바꾸기)으로 쓰지 않는다.
  - 훅: 목록의 파일·`.approved`를 Edit/Write하면 사장 확인 창, Bash로 `.approved`·승인 스크립트를 건드리면 막음(읽기 명령은 통과), 어떤 방법으로든 바뀌면 커밋 직전·응답 끝에 해시가 달라 막음(`check-approved.sh`).
- 테스트와 다르게 만드는 게 낫다고 생각되면 코드를 테스트에 맞추고, 의견은 질문으로 남긴다.
- 화면 구조가 바뀌어 요소를 못 찾게 되면: **검사 내용과 숫자는 그대로, 찾는 위치만** 바꾸겠다고 보여 주고 다시 승인받는다.
- 테스트 준비 코드(`conftest.py`, 기다리는 시간, 테스트용 서버, `tests/run.sh`)는 검사 내용이 아니므로 고칠 수 있다. 고친 이유는 `docs/NOTES.md`에.

## 고치는 방법
- **테스트 환경 탓인 실패를 앱 코드로 우회하지 않는다.** 테스트 준비 코드를 고친다.
- 리뷰·레드팀에서 나온 문제는 고치기 전에 그 문제를 잡는 회귀 테스트를 먼저 넣어 실패를 확인한다. 회귀 테스트는 승인 목록과 섞지 않고 `tests/test_review_fixes.*`에 둔다.
- 테스트 하나를 3번 고쳐도 통과하지 않으면 멈추고 superpowers:systematic-debugging으로 원인부터 찾는다. 그래도 안 되면 계속하지 말고 **멈추고 사장에게 보고**한다.
- 구현·다시 고치기 루프는 `/goal` 한 문장으로 돌고, 매 회차 `docs/progress.md`에 기록한다(`/build-app` "구현 루프").

## 돌리기
- 테스트는 직접 돌리지 말고 `test-runner` 에이전트에게 맡겨 요약만 받는다(긴 로그는 `docs/test-log.txt`).
- 실행 명령은 `apps/<앱>/HANDOFF.md`의 `테스트 실행:` 줄 하나. 훅이 이 줄을 읽어 커밋 전에 돌린다. 허용 명령과 형식은 `/build-app` "HANDOFF 형식" 절.
- 파이썬 테스트는 `bash tests/run.sh`(견본 `.claude/skills/build-app/templates/run.sh`).

# apps/<앱>/HANDOFF.md 형식 — 앱 HANDOFF를 처음 만들거나 `테스트 실행:`·`포트:` 줄을 고칠 때 읽는다

## apps/<앱>/HANDOFF.md 형식
```markdown
# <앱이름>
현재 단계: <1~6> (<단계 이름>)
한 줄 설명: ...
실행 방법: ...
테스트 실행: `<명령>`
포트: <이 앱이 쓰는 포트, 예: 8081 5174 — 앱마다 다르게>
리뷰 기준: <4단계 시작 직전 커밋>
결과: 테스트 N/N 통과 (YYYY-MM-DD 확인)
사용자에게 남은 질문: ...
다음 할 일: ...
```

`테스트 실행:` 줄은 훅(`.claude/hooks/check-tests.sh`)이 읽어서 커밋 전과 응답을 끝내기 전에 실행한다. 3단계에서 테스트를 만들면 바로 채운다. 이 줄은 한 줄, 백틱 안, 앱 폴더에서 bash로 실행되는 명령이어야 한다. 훅은 `npx playwright test`, `npx vitest run`, `npm test`, `npm run test`, `node --test`, `./gradlew test`, `gradle test`, `./mvnw test`, `mvn test`, `(python -m) pytest`, `bash tests/<파일>.sh`로 시작하고 뒤에 옵션만 붙은 명령만 실행한다 (`;` `|` `&` `$` 금지). 이 밖의 도구가 필요하면 `tests/run.sh`에 담아 `bash tests/run.sh`로 적는다. 훅이 막으면 우회하지 말고 실패를 고친다.

**`포트:` 줄과 잠금**(`.claude/hooks/lock.sh`, `docs/org.md` "잠금"): 테스트는 실행 전에 `포트:` 줄의 포트마다 잠금(`env:port:<번호>`)을 잡고 돈다. 다른 세션·Stop 훅이 같은 포트로 테스트 중이면 **먼저 온 순서대로 기다린다**(실패로 치지 않음). `포트:` 줄이 없으면 모든 앱이 `env:port:default` 하나에 줄을 서서 앱끼리도 동시에 못 돈다 — 그래서 앱을 만들 때 **앱마다 다른 포트**(백엔드 8081·8082 …, 화면 5174·5175 …)를 정해 `포트:` 줄과 `playwright.config`·`backend.sh`의 `PORT`에 같이 적는다. 줄이 오래 막히면 `bash .claude/hooks/lock.sh status`로 누가 잡았는지 본다(끝난 작업은 자동 회수, 살아 있는데 오래 걸리면 '지연' → 사장 보고).

**테스트 도구의 합계 줄이 출력에 나와야 한다.** graph.sh(bf·tr·sc)는 exit 0만 믿지 않고 출력에서 개수를 읽어 "통과 수 ≥ 승인된 테스트 수, 건너뜀 0"일 때만 통과시킨다. 개수를 못 읽으면 통과가 아니다. 합계 줄을 지우는 옵션(`--reporter=dot`의 조용한 모드, `> /dev/null` 등)을 쓰지 않고, Gradle은 `build.gradle`에 `test { testLogging { events "passed", "skipped", "failed" } }`를 넣는다. 읽는 형식은 graph.md "테스트 개수 읽기".

**파이썬 테스트는 `bash tests/run.sh`로 적는다.** 컴퓨터마다 명령이 달라서(Windows는 `py`, Mac은 `python3`, Windows의 `python`은 가짜일 수 있음) `run.sh`가 pytest가 깔린 파이썬을 찾아 쓰게 한다. 견본: `.claude/skills/build-app/templates/run.sh`를 `apps/<앱>/tests/run.sh`로 복사해 쓴다.

구현 중(테스트 일부 실패)에 응답을 끝내면 Stop 훅이 한 번 멈춰 세운다. 그때는 "아직 완성 아님, 무엇이 실패 중인지"만 짧게 알리고 계속한다.

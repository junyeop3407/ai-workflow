---
name: handoff
description: Use when a step of work is finished, before stopping a session, or when switching computers ("마무리해 줘", "올려 줘", "/handoff") — updates HANDOFF.md, commits, and pushes so another computer can continue.
---

# handoff — 단계 마무리 (HANDOFF 갱신 → 커밋 → 푸시)

이 저장소는 여러 컴퓨터에서 이어 작업한다. **대화 기록에만 있는 정보는 다른 컴퓨터에서 사라진다.** 그래서 단계가 끝날 때마다 이 순서를 지킨다.

## 순서
1. `git pull` — 다른 컴퓨터에서 한 작업을 먼저 받는다. 충돌이 나면 멈추고 사장에게 쉬운 말로 알린다.
2. **레드팀 표시 확인**: `apps/<앱>/.redteam-needed`가 있으면 민감한 파일을 고친 뒤 레드팀을 아직 안 돌린 것이다. 중간 저장(작업 중 커밋)은 그대로 진행하되 앱 HANDOFF의 다음 할 일 맨 위에 "레드팀 다시 돌리기"를 적는다. 6단계 마무리·배포라면 먼저 `/build-app` "레드팀 공격"을 끝낸다. 표시 파일은 지우지 말고 함께 커밋한다.
3. **앱 HANDOFF 갱신** (`apps/<앱>/HANDOFF.md`, 형식은 `/build-app` "HANDOFF 형식"): 현재 단계(graph.sh가 state.json에 맞춰 자동으로 적는다. 손으로 바꾸지 않는다), `apps/<앱>/state.json`도 함께 커밋, 결과(테스트 N/N 통과 + 날짜), 사용자에게 남은 질문, 다음 할 일. 구현 중이면 `docs/progress.md`(구현 일지)도 마지막 회차까지 적혀 있는지 확인한다.
   - **"완료"는 사장에게 "해결됐어요"를 받은 뒤에만** 쓴다(`/build-app` "사장 확인 루프"). 받기 전이면 "사장 확인 대기".
4. **루트 HANDOFF 갱신** (`HANDOFF.md`): 앱을 끝냈을 때, 또는 중간에 멈출 때만. 로드맵 표와 "마지막 갱신" 날짜. **푸시할 때마다** 맨 위 `마지막 작업 컴퓨터: <Windows|Mac> <YYYY-MM-DD HH:MM> (<브랜치>)` 줄을 고친다(`uname -s`: Darwin = Mac, MINGW·MSYS = Windows). 다음 컴퓨터의 세션 시작 점검이 이 줄을 보여 준다.
5. **커밋**: 한 커밋에 한 가지 일. 메시지는 한국어로 "무엇을, 왜" (예: `가계부: 월별 합계 추가 — 사장 요청`).
   - 커밋 메시지는 `git commit -m "..."` 한 줄로 쓴다(-F·heredoc은 승인 단어 검사에 막힐 수 있음).
   - git add / commit / pull / push / cd는 `&&` `;`로 잇지 말고 한 줄에 하나씩 실행한다(승인 단어가 든 명령에 붙이면 막힘).
   - 테스트가 실패하는 상태로는 커밋하지 않는다(훅이 막는다). 훅이 막으면 우회하지 말고 고친다.
   - 비밀값·`.env`·컴퓨터 전용 경로가 섞이면 훅이 막는다. 그 파일을 빼고 다시 커밋한다.
   - 3단계(테스트만 쓴 상태)는 커밋하지 않는다. 상태만 HANDOFF에 적고 4단계 통과 후 함께 커밋.
6. **푸시**: `git push`. 강제 푸시는 하지 않는다(훅이 막는다). 거절되면 1번부터 다시.
7. 사장에게 한 줄로: 무엇을 올렸는지 + 다음 할 일.

## 세션을 끝낼 때
- 대화가 길어져 흐름을 놓칠 것 같으면 이 절차를 마치고 새 세션에서 "HANDOFF.md 읽고 이어서 해 줘"(앱은 "/build-app 이어서")를 하자고 제안한다.
- 커밋 전 파일은 다른 컴퓨터로 따라가지 않는다. 옮기기 전에 이 절차를 끝낸다.

## 다른 컴퓨터로 옮길 때 (집 Windows ↔ 밖 Mac, 사장 결정 2026-11-23)
사장이 "나갈게", "마무리해 줘", "맥에서 할게"처럼 말하면 위 순서대로 하되, **테스트가 아직 실패하는 중**(구현 중)이면 main 대신 **임시 브랜치**로 올린다.
1. 테스트가 통과하면 → 위 순서 그대로(main).
2. 실패 중이면 → `git switch -c wip/<앱>`(이미 있으면 `git switch wip/<앱>`) → 위 3·4번(HANDOFF에 "임시 브랜치 wip/<앱>에서 구현 중, 실패 N개: …"를 다음 할 일 맨 위에) → `git add <앱 폴더>` → `git commit -m "<앱>: 구현 중 옮김(테스트 N/M) — 다른 컴퓨터에서 이어 하려고"` → `git push -u origin wip/<앱>`. 커밋 훅은 `wip/` 브랜치에서만 실패 상태 커밋을 허용한다. 승인된 테스트 잠금·비밀값 검사는 그대로 돈다. 예외는 **`git commit -m "…"` 하나만 있는 명령**일 때만 — 다른 명령을 `;`·`&&`·`|`로 붙이거나 메시지에 `;`·`&`·`|`·영어 switch·checkout·reset·branch·worktree가 들어가면 예외 없이 막힌다(브랜치를 바꿔 속이는 것 차단). 브랜치 바꾸기는 커밋 전에 따로 한 줄로.
3. 사장에게: "임시 브랜치 wip/<앱>에 올렸어요. Mac에서 열면 세션 시작 점검이 알려 줍니다."
- **이어 받을 때**(다른 컴퓨터): 세션 시작 점검이 원격의 `wip/…`를 알려 주면 `git switch wip/<앱>` → `git pull` → 이어서 구현.
- **다시 main으로**(테스트가 다 통과하면): wip에서 커밋·푸시 → `git switch main` → `git pull` → `git merge --squash wip/<앱>` → `git commit -m "<앱>: <한 일> — 임시 브랜치 합침"`(이 커밋에서 테스트 확인) → `git push` → 로컬 `git branch -D wip/<앱>`. 그대로 합치기(`git merge wip/…`·cherry-pick·`pull … wip/…`·`reset … wip/…`), `…:main` 푸시(따옴표로 감싸도), 추적 대상이 main인 wip에서 push, 푸시·추적 설정 바꾸기, main 이름 바꾸기·강제 옮기기·update-ref는 훅이 막는다. Claude Code 훅은 명령 글자를 읽어 판단하므로 빈틈이 남는다 — 그래서 **마지막 방어선은 git 자체 훅 `.githooks/pre-push`**: main(master)으로 올라가는 커밋은 지금 체크아웃한 커밋이고 커밋 안 한 변경이 없을 때만, 바뀐 앱의 테스트를 실제로 돌려 통과해야 올라간다(어떤 방법으로 만든 커밋이든). 세션 시작 훅이 컴퓨터마다 `core.hooksPath=.githooks`로 연결하고, `--no-verify`·`core.hooksPath` 바꾸기는 guard-git이 막는다. main push는 테스트 시간만큼 걸린다.
- **원격 임시 브랜치 지우기는 Claude가 못 한다**(브랜치 삭제는 훅이 막음, 안전 검사도 풀어 주지 않음). 합친 뒤 사장에게 이 한 줄을 붙여 넣어 달라고 한다: `! git push origin --delete wip/<앱>` — 안 지워도 문제는 없고, 세션 시작 점검에 계속 보일 뿐이다.
- 한 앱에 임시 브랜치는 하나만. main에 합치기 전에 다른 앱 일을 시작하지 않는다(두 브랜치에 흩어지지 않게).

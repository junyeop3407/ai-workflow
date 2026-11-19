---
name: weekly-review
description: Use when the user says "/weekly-review", "주간 회고", or accepts the session-start prompt that 7+ days have passed since the last weekly review — finds mistakes repeated 2+ times in the last 7 days and proposes at most 3 new rules for the boss to pick.
---

# weekly-review — 주간 회고 (반복된 실수 → 규칙 후보 최대 3개)

예약 작업은 쓰지 않는다(사장 컴퓨터는 밤에 꺼짐). 세션을 열 때 훅(`session-start.sh`)이 "7일 지남"을 알려 주면 사장에게 한 번 묻고, "응"이면 이 순서로 한다.

## 순서
1. `git pull`.
2. **읽기** (지난 7일):
   - `git log --since="7 days ago" --stat` — 커밋 메시지와 바뀐 파일
   - 각 앱: `apps/*/docs/NOTES.md`, `progress.md`, `review_result.md`(Gemini), `review_codex.md`(Codex), `redteam.md`, `review.md`(qa-reviewer)
   - 에이전트 메모리: `.claude/agent-memory/*/MEMORY.md`
   - 파일이 많으면 읽기를 에이전트(Explore)에게 맡기고 "반복된 실수 목록"만 받는다.
3. **찾기**: **2번 이상 반복된 실수**만 고른다(같은 앱 안 2번, 또는 다른 앱에서 같은 종류). 한 번 나온 일은 버린다. 예: "빈 목록 화면 처리 누락이 리뷰에서 3번", "같은 테스트가 /goal 브레이크에 2번 걸림", "Codex·Gemini가 같은 입력 검증 누락을 2번".
4. **제안**: 규칙 후보를 **최대 3개** 표로 보여 준다. 반복이 없으면 "이번 주 반복된 실수 없음"으로 끝낸다(억지로 만들지 않는다).
   | # | 반복된 실수 (횟수·근거 파일) | 넣을 규칙 (한 문장) | 넣을 곳 | 추천 |
   |---|---|---|---|---|
   - 넣을 곳은 저장소 규칙대로: 매번 알아야 하는 사실 → `CLAUDE.md`, 한 주제·경로 → `.claude/rules/`, 절차 → 스킬, 절대 어기면 안 되는 것 → 훅, 검수 관점 → 에이전트.
   - 이미 있는 규칙과 겹치면 새로 넣지 말고 "기존 규칙 X를 더 눈에 띄게"로 제안한다.
5. **고르기**: AskUserQuestion(multiSelect)으로 사장이 고르게 한다. **전부 반영하지 않는다** — 규칙이 너무 많아지면 오히려 안 지켜진다. 고른 것만 반영한다(CLAUDE.md는 짧게 유지).
6. **기록**: `docs/last-weekly-review.txt`를 오늘 날짜(`YYYY-MM-DD`) 한 줄로 바꾼다. 아무것도 고르지 않았어도 바꾼다(회고는 한 것).
7. `/handoff` — 커밋 메시지 예: `주간 회고: <규칙 요약> 추가 — 지난주 <실수> N번 반복`.

## 하지 않을 것
- 사장이 고르지 않은 후보를 반영하기.
- 메모리·회고 기록에 앱의 키·토큰·개인정보·공격 증거 원문을 옮겨 적기(이 저장소는 공개).
- /schedule·데스크톱 예약 작업 만들기.

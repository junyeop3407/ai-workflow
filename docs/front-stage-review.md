# 앞단계(사람이 정하는 단계) 보완 분석

작성: 2026-11-22 · 상태: **①~⑧ 반영함**(사장 OK, 2026-11-22) · 아래 "6. 추가로 찾은 것" ⑨~⑬은 **사장 검토 대기**

반영한 곳: ①②⑦ `build-app/SKILL.md` "기획 인터뷰" + `templates/requirements.md` · ③ `doc-review.sh`(Gemini=agy) · ④ "사전 부검" + `docs/premortem.md` · ⑤ 수용 기준 `F1-1` · ⑥ `graph.sh` 검사 `req`·`trace`·`undecided`(시험 `test-graph.sh` G절) · ⑧ "★ 검토 요청 틀" + CLAUDE.md

"앞단계"는 사장이 무엇을 만들지 정하는 구간이다: `req → ★기획 검토 → opt → ★설계 선택 → tl → ★테스트 승인 → ip → ★계획 승인 → ui·dd → ★디자인·데이터 검토`.
이 뒤는 자동 루프라서, 앞단계에서 빠진 것은 뒤에서 고치느라 몇 배로 비싸진다. 레퍼런스들이 공통으로 말하는 것도 같다: **사람의 일은 "무엇을 왜 만들지 정하고, 결과를 검증하는 것"**이다.

## 1. 레퍼런스

| # | 레퍼런스 | 앞단계에 쓸 핵심 |
|---|---|---|
| A | 실밸개발자 영상 43편 (사장 제공) | 4번 전략적 사고(목표 지표부터 합의) · 11번 스펙 주도 개발(입출력·관측 가능한 동작·제약·완료 기준) · 17번 채점기 먼저, 만드는 쪽과 채점 쪽 분리 · 19번 Grill me(결정 트리 인터뷰) · 31번 첫 계획은 바로 실행하지 말고 여러 번 재검토, MVP 제외 사항 명시 · 43번 "나에게 먼저 질문해줘"(역질문) |
| B | 보스턴빌더 영상 19개 (사장 제공) | 돈·발송·삭제처럼 되돌리기 어려운 일은 사람이 마지막에 확인 · 반복되는 일 하나부터 작게 |
| C | 토비의 스프링 영상 23개 (사장 제공) | AI 시대 실력 = 일을 정의하고 검증하는 능력 · 1차 출처로 직접 확인 · 기술은 목적이 있을 때 |
| D | Anthropic Claude Code 공식 모범 사례 | 스펙이 불확실하면 Claude가 객관식으로 인터뷰해 SPEC.md를 쓰고, 새 세션에서 구현 · "통과/실패로 답하는 확인 수단"을 줄 것 |
| E | Matt Pocock `grill-me` 스킬 | 결정 트리를 가지별로, 앞선 결정부터 물음 · 질문마다 추천 답 · 코드로 알 수 있는 건 묻지 않고 직접 찾음 · 공유된 이해에 닿을 때까지 |
| F | GitHub Spec Kit | constitution → specify → **clarify(한 번에 최대 5문항, 답을 spec에 바로 반영)** → plan → tasks → **analyze(구현 전에 spec·plan·tasks 사이 모순 검사)** |
| G | AWS Kiro + EARS 표기법 | 요구사항을 "언제 ~하면, 시스템은 ~한다" 형태 수용 기준으로 → 모호하지 않고 테스트로 옮기기 쉬움 |
| H | Shape Up (Basecamp) | appetite(얼마만큼의 시간·비용을 걸지 먼저) · rabbit holes(시간을 빨아들일 위험한 곳) · no-gos(일부러 안 할 것) |
| I | 사전 부검 (Gary Klein) | "이미 실패했다"고 가정하고 이유를 적음. 계획이 확정되기 **전에** 해야 효과가 있음 |

## 2. 지금 잘 되어 있는 것 (유지)
- 질문은 AskUserQuestion으로 보기 + 추천, 한 번에 하나 (D·E와 같은 방향)
- 기획서에 "하지 않을 것" (H의 no-gos)
- 기능 F번호 → 테스트 목록 대응 (추적성)
- 견본 파일(변환 전/후)로 정답을 실제 파일에서 받음 (C의 "직접 확인")
- spec.md "아직 안 정한 것"에 적고 지어내지 않음
- 설계안 3개 + 버린 안과 이유 (ADR과 같은 역할)
- 계획 모드에서 승인 후 구현 (D·F)

## 3. 빈 곳과 보완안 (중요한 순)

### ① 목표와 성공 기준이 없다 → "이 앱이 잘 됐다는 증거" 1~3개를 먼저 정한다
- 근거: A4·A17·D("통과/실패로 답하는 확인 수단")·C
- 지금: 기획서가 "기능 목록"에서 시작한다. 완성도 90%도 기능 통과율이지 "사장이 원한 결과가 났는가"가 아니다.
- 보완: req 첫 질문으로 "이 앱을 쓰면 무엇이 얼마나 나아지나요?"(보기: 시간 줄이기 / 실수 줄이기 / 돈 / 재미 …) → 기획서 맨 위 `## 성공 기준`에 측정 가능한 한 줄씩(예: "엑셀 정리 30분 → 1분", "틀린 칸 0개"). 6단계 QA 보고에 성공 기준별 ✓/✗를 넣는다.

### ② 인터뷰가 얕다 → 빈칸 점검표로 "결정 트리"를 끝까지 묻는다
- 근거: D·E·F(clarify)·A19·A43
- 지금: "최소한 누가, 어디서, 꼭 되어야 할 기능, 저장이 필요한지" 4가지. 나머지는 구현 중 "아직 안 정한 것"으로 미뤄진다.
- 보완: req에 **빈칸 점검표**를 두고, 칸마다 "정함 / 묻기 / 나중(이유)"이 될 때까지 묻는다.
  `사용자·상황 · 성공 기준 · 꼭 되어야 할 기능 · 하지 않을 것 · 데이터(무엇을 저장, 민감 정보, 지우기) · 되돌리기 어려운 동작(돈·발송·삭제) · 로그인·권한 · 외부 연결 · 폰/PC · 예외(빈 값·끊김) · 예산(시간·비용)`
  - 규칙: 앞선 결정부터(누가 → 무엇 → 어떻게), 한 번에 1개(AskUserQuestion 한 번에 최대 4개까지 가능하지만 초보 기준 1개), 질문마다 추천 답, **저장소·견본 파일로 알 수 있는 건 묻지 않는다**, 한 바퀴 최대 5문항(F) 후 기획서 초안을 보여 주고 다음 바퀴.
  - 끝나는 조건: 점검표에 "묻기"가 0개.

### ③ 기획서를 만든 AI가 스스로 OK한다 → ★ 전에 다른 AI가 비판한다
- 근거: A17(만드는 쪽·채점 쪽 분리)·A31(첫 계획을 바로 쓰지 말고 재검토)·`ai-team.md`(기획서는 `agy -p`로 2차 검토라고 이미 적혀 있음)
- 지금: ai-team.md엔 "기획서 2차 검토"가 있지만 graph.md req 노드에는 없다 → 실제로는 안 돈다.
- 보완: req 통과 조건에 "Gemini(agy) 기획서 비판 1라운드 → 맞는 지적 반영 → `docs/review_req.md`"를 넣는다. 사장에게는 반영한 것/안 한 것만 한 줄씩.

### ④ 위험을 미리 안 본다 → 설계 선택 전에 사전 부검
- 근거: I·H(rabbit holes)
- 지금: 설계안 점수표에 장단점은 있지만 "어디서 망할까"는 없다.
- 보완: opt에서 고른 추천안에 "이 앱이 3주 뒤 실패했다면 이유 5개" → 가능성·영향 높은 것 2~3개는 막는 방법(테스트·설계 변경·하지 않을 것으로 이동)을 적어 ★설계 선택 때 함께 보여 준다. 계획 승인 뒤에 하면 형식만 남는다(I).

### ⑤ 기능이 테스트로 바로 안 옮겨진다 → 기능마다 수용 기준 문장
- 근거: G(EARS)·A11(관측 가능한 동작·완료 기준)
- 지금: F번호 기능은 "무엇을"까지. 테스트 목록(tl)에서 QA팀이 해석한다.
- 보완: 기능마다 `F1-1. [언제/조건]이면 앱은 [보이는 결과]를 한다` 꼴 1~3줄. 사장도 읽기 쉽고 tl은 이걸 그대로 테스트로 옮긴다.

### ⑥ 문서끼리 어긋나도 모른다 → 계획 승인 전에 자동 대조 (⚙️)
- 근거: F(analyze)
- 보완: graph.sh가 ip 통과 때 대조: requirements의 F번호마다 tests.md에 테스트가 있고, tests.md의 테스트는 모두 F번호를 가리키고, spec.md "아직 안 정한 것"에 구현 필요 항목이 남아 있지 않은지. 단순 비교라 AI가 아니라 프로그램이 한다(graph.md 원칙).

### ⑦ 되돌리기 어려운 동작을 앱 설계에서 따로 안 다룬다
- 근거: B·A9(결제·외부 전송은 확인 절차)
- 보완: ②의 점검표에서 "돈·메시지 발송·삭제"가 있으면 spec.md에 **확인 절차**(사용자에게 한 번 더 묻기, 되돌리기, 기록)를 기능으로 넣고, 테스트 목록에도 넣는다.

### ⑧ 사장 검토 자료가 길어질 수 있다 → 1쪽 요약 형식 고정
- 근거: A6(에이전트 보고는 불릿 5개, 시각 자료)
- 보완: 모든 ★에서 같은 틀: `결정할 것(맨 위) · 한눈 요약 불릿 5개 이하 · 그림(Mermaid·캡처) · 추천과 이유 · 위험 1~2개`.

## 4. 참고만 (이번엔 하지 않음)
- CLAUDE.md 길이: A2·A27은 100줄 이하 "지도"를 권함. 지금 118줄. 앞단계와는 별개라 따로 다룰 일.
- 세컨드 브레인(A3·A25): 사장의 취향·결정 이유를 앱 사이에 쌓는 일. 앱이 여러 개 생긴 뒤에 의미가 있음.
- Eval(A3): 스킬 효과를 점수로 비교. 첫 앱 이후에.

## 5. 직원 추천
- **먼저 할 것: ①·②·③·④** — 사장이 직접 체감하는 앞단계 품질을 가장 크게 올리고, 규칙·graph.md·SKILL.md 수정만으로 된다.
- **이어서: ⑤·⑥** — ⑥은 graph.sh 코드 변경 + 시험(test-graph) 추가가 필요하다.
- ⑦·⑧은 ②·①을 넣을 때 같이 들어가는 작은 변경.
- 늘어나는 사장 부담: 질문이 몇 개 늘지만 모두 클릭 보기, 대신 구현 뒤 "아직이에요" 왕복이 줄어든다.

## 6. 추가로 찾은 것 (⑨~⑬, 사장 검토 대기)

| # | 레퍼런스 | 지금 빈 곳 | 보완안 | 크기 |
|---|---|---|---|---|
| ⑨ | Example Mapping (Matt Wynne, BDD) — 규칙(파랑)·예시(초록)·질문(빨강) 카드 | 수용 기준이 규칙 문장뿐이라 "얼마나·어떤 값"이 모호할 수 있음 | 수용 기준마다 **구체 예시 하나**: `F1-1 … — 예: 사과 2개 담기 → 장바구니 2`. 테스트가 예시 값을 그대로 씀. 답 못 한 질문은 점검표 `묻기`로 | 작음(견본·인터뷰 한 줄) |
| ⑩ | Amazon Working Backwards (PR/FAQ) | 한 줄 요약만 있어 "사용자에게 무엇이 좋아지나"가 약할 수 있음. 만드는 중 범위가 커져도 잡을 기준이 없음 | 기획서 맨 위에 **사용자에게 보내는 출시 안내문 3문장 + 예상 질문 3개**. ok-qa 때 "안내문에 없는 걸 만들었나(과잉)"를 같이 확인 | 작음 |
| ⑪ | User Story Mapping (Jeff Patton) — 걸어 다니는 뼈대·릴리스 자르기 | 첫 버전 범위를 "하지 않을 것"으로만 정함 | 첫 버전 = **처음부터 끝까지 한 번 도는 가장 작은 흐름**. 기능에 `1차/나중` 표시, `나중`은 테스트·구현에서 빠짐 | 중간(graph.sh 대조 검사가 `나중` 기능을 빼야 함) |
| ⑫ | Kano 모델 — 꼭 있어야(must-be)·많을수록 좋음·있으면 놀람 | 기능 우선순위 기준이 없음 | 인터뷰에서 기능마다 셋 중 하나를 고르게 → 1차는 "꼭" + 핵심 "많을수록", "놀람"은 나중 후보. ⑪과 한 번에 | 작음(⑪과 함께) |
| ⑬ | 저충실도 시제품(종이·와이어프레임) + 실밸 43번(UI는 서비스의 지도) | 화면 모양은 4단계 디자인에서야 처음 봄 → 기획 단계에서 흐름이 틀려도 늦게 발견 | ★기획 검토 때 **손그림 수준 화면 초안**(회색 상자 HTML 한 장 캡처, 디자인 아님)을 함께 보여 줌 | 중간(캡처 단계 추가) |

이미 있는 것과 겹쳐서 넣지 않을 것: Definition of Ready(INVEST) — req·trace·undecided 검사가 사실상 "구현 시작 준비 점검" 역할을 한다.

**직원 추천**: ⑨·⑩·⑫는 기획서 견본과 인터뷰에 몇 줄 넣는 작은 일이라 바로 넣고, ⑪은 graph.sh 대조 검사를 고쳐야 해서 ⑫와 묶어 그다음, ⑬은 사장이 "화면을 일찍 보고 싶다"면 넣는다.

## 출처
- 사장 제공: 실밸개발자 유튜브 영상 분석 정리본, 보스턴빌더 영상별 정리본(전체 목차), 토비의 스프링 영상 분석 정리본(종합 정리) — 2026-11-21 작성본
- Anthropic, Claude Code Best practices: https://code.claude.com/docs/en/best-practices
- Matt Pocock, grill-me: https://www.skills.sh/mattpocock/skills/grill-me
- GitHub Spec Kit: https://github.github.com/spec-kit/ · Microsoft 소개 글: https://developer.microsoft.com/blog/spec-driven-development-spec-kit/
- Kiro Specs: https://kiro.dev/docs/specs/concepts · EARS: https://en.wikipedia.org/wiki/Easy_Approach_to_Requirements_Syntax
- Shape Up, Write the Pitch: https://basecamp.com/shapeup/1.5-chapter-06
- Gary Klein, pre-mortem: https://www.psychologytoday.com/ie/blog/seeing-what-others-dont/202101/the-pre-mortem-method
- Example Mapping: https://cucumber.io/blog/example-mapping-introduction · https://automationpanda.com/2018/02/27/bdd-example-mapping/
- Working Backwards: https://www.allthingsdistributed.com/2006/11/working_backwards.html · https://productschool.com/blog/product-fundamentals/prfaq
- User Story Mapping: https://www.oreilly.com/library/view/user-story-mapping/9781491904893/ch16.html
- Kano 모델: https://www.surveymonkey.com/learn/market-research/kano-model-prioritize-features
- 저충실도 시제품: https://ux.byu.edu/low-fidelity-prototyping · https://open.oregonstate.education/setextbook/chapter/paper-prototyping/
- Definition of Ready: https://www.atlassian.com/agile/project-management/definition-of-ready

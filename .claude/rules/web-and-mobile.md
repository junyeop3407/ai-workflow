---
paths:
  - "apps/**/*.{tsx,ts,jsx,js,css,html}"
  - "apps/**/capacitor.config.*"
  - "apps/**/android/**"
  - "apps/**/ios/**"
  - "apps/*/docs/DESIGN.md"
---

# 웹 + 앱(안드로이드·iOS) 화면 규칙

## 웹과 앱은 동시에
- 화면은 React 한 벌로 만들어 웹으로 열리게 하고, 같은 코드를 Capacitor로 앱으로 포장한다. 웹 전용·앱 전용 화면을 따로 만들지 않는다.

## 안드로이드와 iOS 둘 다
- Capacitor로 `android`·`ios` 두 플랫폼을 모두 추가한다. 한쪽에서만 되는 기능(플랫폼 전용 플러그인 등)은 쓰지 않는다. 꼭 필요하면 다른 쪽 대체 방법까지 함께 만든다.
- 화면은 폰 크기(안드로이드·아이폰 둘 다)에서 깨지지 않게 만들고, 아이폰 노치·하단 바 영역(safe area)을 고려한다.
- 안드로이드 빌드는 Android Studio, iOS 빌드는 Mac + Xcode가 필요하다. Mac이 없는 컴퓨터에서는 iOS 빌드를 건너뛰고 "iOS는 Mac에서 빌드 필요"라고 사장에게 알린다(웹·안드로이드는 그대로 진행).

## 최신 웹 표준으로 (modern-web-guidance, 사장이 말하지 않아도 항상)
- 화면 코드(HTML·CSS·JS/TS·React)를 **새로 짜거나 고치기 전에** `modern-web-guidance` 스킬로 그 작업의 가이드를 먼저 찾아 읽고 따른다. 예: 모달 → "accessible modal dialog", 드롭다운 → "popover menu". div + 자바스크립트로 흉내 내지 말고 브라우저 기본 기능(`<dialog>`, popover, `:has()`, 컨테이너 쿼리 등)을 쓴다.
- 스킬이 없으면 직접 `npx -y modern-web-guidance@latest search "<하고 싶은 것>"` → `retrieve <ID>`로 찾는다. 둘 다 안 되면 "필요한 것이 없을 때"(CLAUDE.md)대로 멈추고 알린다.
- **iOS가 기준이다.** 앱은 iOS Safari(WKWebView)에서도 열려야 하므로 가이드가 권하는 기능이라도 **Baseline "Widely available"**인 것만 그냥 쓴다. "Newly available"이나 Safari 미지원 기능은 대체 방법(폴백)을 함께 만든다.
- 가이드는 화면(프론트) 코드에만 쓴다. 백엔드(Java + Spring)에는 해당 없음.
- 이미 만든 앱을 이어 할 때는 4단계 시작 전에 한 번 "이 앱에서 옛날 방식으로 짠 웹 코드 찾아서 요즘 방식으로 바꿀 수 있는 것" 점검을 돌리고, 바꿀 목록을 `docs/plan.md`에 넣는다. 점검이 모든 패턴을 잡지는 못하니 결과는 직접 확인한다.

## 디자인 규칙대로
- 디자인팀이 먼저 쓴 `apps/<앱>/docs/DESIGN.md`(색·글꼴·간격·컴포넌트)를 따른다. 규칙에 없는 색·간격을 새로 만들지 않는다. Tailwind CSS 사용.
- 완성 전 폰·PC 크기 화면을 캡처해 DESIGN.md대로인지 확인한다.
- DESIGN.md "참고" 절의 "베끼지 말 것"(다른 회사 로고·이름·고유 아이콘·일러스트·문구)은 화면에 넣지 않는다.

## 프론트에 두지 않는 것
- 비밀 키, 금액 계산, 권한 판단은 넣지 않는다(백엔드에만). 앱 파일은 누구나 열어볼 수 있다.

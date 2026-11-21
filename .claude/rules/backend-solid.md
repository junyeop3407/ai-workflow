---
paths:
  - "apps/**/*.java"
  - "apps/**/*.kt"
  - "apps/**/build.gradle*"
  - "apps/**/pom.xml"
  - "apps/*/docs/api.md"
  - "apps/*/docs/data.md"
---

# 백엔드 설계 규칙 (SOLID · Java + Spring)

백엔드팀은 아래 다섯 원칙을 **위반 신호가 하나도 없게** 짠다. 원칙마다 "무슨 뜻 → Spring에서 이렇게 → 이러면 위반"으로 적었다.
`ponytail`(필요한 만큼만)과 부딪히지 않게, **쓰지 않는 확장을 미리 만드는 것도 위반**으로 본다(맨 아래 "과하게 하지 않기").

## 기본 구조 (모든 원칙의 바탕)
```
controller  → 요청 받기·입력 검증(@Valid)·응답 DTO 만들기만. 업무 규칙 없음
service     → 업무 규칙 하나의 흐름(유스케이스). 트랜잭션은 여기서
domain      → 엔티티·값 객체. 자기 데이터로 할 수 있는 계산·검사는 엔티티 메서드로
repository  → 저장·조회만 (Spring Data 인터페이스)
infra/      → 결제·메일·파일 저장·외부 API 같은 바깥 연결의 구현
```
- 의존 방향은 `controller → service → domain/repository`, 바깥 연결은 `service → (인터페이스) ← infra 구현`. 거꾸로(서비스가 컨트롤러·HTTP 객체를 앎, 도메인이 서비스를 앎) 가지 않는다.
- 패키지는 기능 단위로 나눈다(`order/`, `member/` 안에 controller·service·repository). 기능끼리는 상대의 **service만** 부르고 repository는 직접 부르지 않는다.

## S — 단일 책임 (Single Responsibility)
**뜻**: 클래스 하나는 바뀌는 이유가 하나뿐이어야 한다.
**Spring에서**: 컨트롤러는 HTTP만, 서비스는 유스케이스 하나(또는 한 기능의 몇 개), 리포지토리는 저장만. 엔티티를 응답으로 그대로 내보내지 않고 응답 DTO를 따로 둔다.
**위반 신호**
- 컨트롤러에 `if`로 된 업무 규칙, 금액 계산, `repository` 직접 호출, `@Transactional`
- 서비스 하나가 서로 다른 기능(주문 + 회원 + 메일 보내기)을 다 하거나, 주입받는 의존성이 **5개를 넘음**
- 클래스 300줄·메서드 40줄을 넘음 (넘으면 나눌 이유를 `NOTES.md`에 적거나 나눈다)
- `XxxManager`·`XxxHelper`·`XxxUtil`에 업무 규칙이 모임
- `@Entity`를 컨트롤러가 그대로 반환하거나 요청 바디로 받음

## O — 개방-폐쇄 (Open-Closed)
**뜻**: 새 종류가 늘 때 기존 코드를 고치지 않고 **새 클래스를 더해서** 넓힌다.
**Spring에서**: 결제 수단·알림 채널·할인 정책처럼 **종류가 2개 이상**이면 인터페이스 + 종류별 구현 `@Component`로 두고, `List<인터페이스>`나 `Map<String, 인터페이스>`로 주입받아 고른다.
**위반 신호**
- 종류(`type`·`enum`·문자열)에 따라 갈라지는 `if-else`·`switch`가 **두 곳 이상**에 똑같이 있음 (새 종류를 더하면 여러 곳을 고쳐야 함)
- 새 종류를 더하려고 기존 서비스 메서드 안을 고쳐야 함
- 한 곳에만 있는 단순 분기는 위반이 아니다 (그대로 둔다)

## L — 리스코프 치환 (Liskov Substitution)
**뜻**: 부모 타입(인터페이스) 자리에 어떤 구현을 넣어도 부르는 쪽이 똑같이 믿고 쓸 수 있어야 한다.
**Spring에서**: 구현은 인터페이스가 약속한 입력·출력·예외를 그대로 지킨다. 구현마다 다른 점은 인터페이스 메서드로 드러낸다(`supports(type)` 등).
**위반 신호**
- 구현이 `UnsupportedOperationException`을 던지거나 아무것도 안 하고 넘어감 (못 하는 일이 있으면 인터페이스를 쪼갠다 → I)
- 부르는 쪽이 `instanceof`·캐스팅으로 구현을 가려 따로 처리함
- 같은 메서드인데 구현마다 `null` 반환 여부·예외 종류가 다름
- 상속(`extends`)을 코드 재사용만을 위해 씀 → 상속 대신 조합(필드로 주입)

## I — 인터페이스 분리 (Interface Segregation)
**뜻**: 쓰는 쪽이 필요한 메서드만 보게 인터페이스를 작게 나눈다.
**Spring에서**: 바깥 연결 인터페이스는 쓰는 곳 기준으로 작게(`PaymentApprover`, `PaymentRefunder`). 읽기 전용이 필요한 곳은 읽기 메서드만 있는 인터페이스를 받는다.
**위반 신호**
- 메서드가 **7개를 넘는** 직접 만든 인터페이스 (Spring Data `JpaRepository` 상속은 제외)
- 구현 클래스에 빈 메서드·`throw new UnsupportedOperationException()`이 있음
- 한 인터페이스를 받는 곳들이 각자 그중 일부 메서드만 씀

## D — 의존 역전 (Dependency Inversion)
**뜻**: 업무 규칙(서비스)은 바깥 기술(결제사 SDK, 메일 서버, 파일 저장소)의 구체 클래스가 아니라 **우리가 정한 인터페이스**에 기대고, 구현은 Spring이 주입한다.
**Spring에서**: 생성자 주입만 쓴다(`private final` 필드 + 생성자 하나, Lombok `@RequiredArgsConstructor` 가능). 바깥 연결은 `service`에 인터페이스, `infra`에 구현. 설정값은 `@ConfigurationProperties`로 받는다.
**위반 신호**
- 필드 주입 `@Autowired private ...`, 세터 주입
- 서비스 안에서 `new`로 의존 객체를 만듦 (`new RestTemplate()`, `new SomeClient()`, `new XxxService()`). 값 객체·DTO·컬렉션의 `new`는 괜찮다
- 서비스가 결제사·메일·클라우드 SDK 클래스를 직접 `import`함
- `static` 메서드·싱글턴으로 외부 시스템을 부름 (테스트에서 바꿔 끼울 수 없음)
- 서비스가 `HttpServletRequest`·`ResponseEntity` 같은 웹 계층 타입을 앎

## 과하게 하지 않기 (이것도 위반)
- 구현이 하나뿐이고 바깥 연결도 아닌 서비스에 `XxxService` + `XxxServiceImpl`을 만들지 않는다. 클래스 하나로 둔다.
- 종류가 하나뿐인데 전략 패턴·팩토리를 미리 만들지 않는다. **두 번째 종류가 생길 때** O 원칙대로 나눈다.
- "나중에 필요할지도" 하는 추상 클래스·제네릭 베이스 서비스를 만들지 않는다.
- 판단 기준: **바깥 연결이거나 종류가 2개 이상이면 인터페이스, 아니면 클래스 하나.**

## 언제 확인하나 (자동으로, 사장에게 묻지 않음)
| 때 | 누가 | 무엇을 |
|---|---|---|
| bb 구현 중, 클래스를 새로 만들거나 고칠 때마다 | 백엔드팀 | 위 "위반 신호"를 스스로 확인하고 짠다 |
| bb 시작 때 | QA팀 | 견본 `.claude/skills/build-app/templates/ArchitectureTest.java`를 `src/test/java/<최상위 패키지>/`에 복사하고 `package`·`ROOT`만 고친다(ArchUnit, `testImplementation 'com.tngtech.archunit:archunit-junit5:<버전>'`). 검사: ① 컨트롤러는 리포지토리를 직접 부르지 않음 ② 필드 주입(`@Autowired`·`@Value` 필드) 없음 ③ 서비스·도메인은 `controller`·`infra` 패키지를 모름 ④ 서비스·도메인은 HTTP 타입을 모름 ⑤ 도메인은 서비스를 모름 ⑥ 기능 패키지 순환 없음. 버전은 **context7로 최신을 다시 확인**한다. 이 테스트는 `백엔드 테스트:` 줄(`./gradlew test`)에 함께 돌아, 위반하면 bb가 통과하지 않는다 |
| cb·cx·gm (Codex·Gemini 검수) | `cross-review.sh` | 자바 변경분에 SOLID 위반 신호도 보라고 요청한다 |
| 5단계 qa | `qa-reviewer` | 바뀐 자바 파일에서 위반 신호를 찾아 `[중간]`으로 지적(`원칙: S/O/L/I/D` 표시). 테스트 실패로 이어지는 것은 `[높음]` |

- SOLID 지적은 취향 지적이 아니다. `ai-team.md`의 "사소한 지적은 모아 두기"에 넣지 않고 그 리뷰 회차 안에서 고친다.
- 위반을 일부러 남겨야 하면(프레임워크 제약 등) 그 자리에 주석 한 줄 + `NOTES.md`에 이유를 적는다. 이유 없는 예외는 없다.

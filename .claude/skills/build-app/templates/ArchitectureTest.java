// 구조 검사 테스트 견본 (.claude/rules/backend-solid.md "언제 확인하나") — bb 시작 때 QA팀이 복사한다.
// 넣는 곳: src/test/java/<ROOT 경로>/ArchitectureTest.java   (맨 위 package 와 ROOT 두 곳만 앱에 맞게 고친다)
// build.gradle:  testImplementation 'com.tngtech.archunit:archunit-junit5:1.5.1'
//   - 버전은 쓰기 전에 context7(또는 Maven Central)으로 최신을 다시 확인한다. 아래 API는 1.5.1 기준으로 확인함
//     (사용자 안내서 archunit.org/userguide, TNG/ArchUnit 소스: AnalyzeClasses·ArchTest·ArchRuleDefinition·GeneralCodingRules·SlicesRuleDefinition)
// `./gradlew test` 에 함께 돌아서, 규칙을 어기면 bb 통과 검사(`백엔드 테스트:` 줄)가 실패한다.
// 규칙을 빼거나 @ArchIgnore 로 끄는 것은 qa-reviewer 가 [높음]으로 지적한다. 예외가 꼭 필요하면 NOTES.md 에 이유를 적는다.
package com.example.app;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.GeneralCodingRules.NO_CLASSES_SHOULD_USE_FIELD_INJECTION;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import com.tngtech.archunit.core.importer.ImportOption.DoNotIncludeTests;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

@AnalyzeClasses(packages = ArchitectureTest.ROOT, importOptions = DoNotIncludeTests.class)
class ArchitectureTest {

    /** 앱의 최상위 패키지 (기능 패키지 order·member 등이 이 아래에 있다) */
    static final String ROOT = "com.example.app";

    // S: 컨트롤러는 HTTP만. 저장소를 직접 부르지 않고 서비스를 거친다
    @ArchTest
    static final ArchRule 컨트롤러는_리포지토리를_직접_부르지_않음 =
            noClasses().that().resideInAPackage("..controller..")
                    .should().dependOnClassesThat().resideInAPackage("..repository..")
                    .allowEmptyShould(true);

    // D: 생성자 주입만. @Autowired·@Value·@Inject·@Resource 필드 금지 (설정값은 @ConfigurationProperties 로)
    @ArchTest
    static final ArchRule 필드_주입_없음 = NO_CLASSES_SHOULD_USE_FIELD_INJECTION;

    // 의존 방향: 업무 규칙(서비스·도메인)은 웹 계층과 바깥 연결 구현을 모른다 (바깥 연결은 인터페이스로)
    @ArchTest
    static final ArchRule 서비스_도메인은_컨트롤러_infra를_모름 =
            noClasses().that().resideInAnyPackage("..service..", "..domain..")
                    .should().dependOnClassesThat().resideInAnyPackage("..controller..", "..infra..")
                    .allowEmptyShould(true);

    // D·S: 서비스·도메인은 HTTP 타입(ResponseEntity, HttpServletRequest 등)을 모른다
    @ArchTest
    static final ArchRule 서비스_도메인은_HTTP_타입을_모름 =
            noClasses().that().resideInAnyPackage("..service..", "..domain..")
                    .should().dependOnClassesThat().resideInAnyPackage("org.springframework.http..", "jakarta.servlet..")
                    .allowEmptyShould(true);

    // 도메인(엔티티·값 객체)은 서비스를 모른다 (의존은 service → domain 한 방향)
    @ArchTest
    static final ArchRule 도메인은_서비스를_모름 =
            noClasses().that().resideInAPackage("..domain..")
                    .should().dependOnClassesThat().resideInAPackage("..service..")
                    .allowEmptyShould(true);

    // 기능 패키지(order, member …)끼리 서로 물고 도는 순환이 없다
    @ArchTest
    static final ArchRule 기능_패키지_순환_없음 =
            slices().matching(ROOT + ".(*)..").should().beFreeOfCycles();
}

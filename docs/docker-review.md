# Docker 도입 분석 — 이 작업장(ai-workflow)에 맞춘 방향

근거: 사장의 "AI 자동화 개발 프로그램 Docker 도입 및 운영 통합 가이드". **분석만 했고 아직 아무것도 바꾸지 않았다.** 반영은 사장 검토 뒤.
대상 컴퓨터: **다른 Windows 컴퓨터 1대 + Mac 1대**(사장 결정 — 지금 이 컴퓨터는 기준이 아님).

## 0. 한 줄 결론
Docker는 **"모든 걸 컨테이너로"가 아니라, 직접 설치하면 아프거나 위험한 곳에만** 쓴다.
1. **DB**(PostgreSQL 등)
2. **레드팀이 공격할 앱**(밖으로 못 나가게 가둠)
3. **두 컴퓨터에서 똑같은 테스트 환경**(버전 고정)
4. 나중에 **Android 빌드**

가이드의 모듈 8개(Docker·Environment·Workspace·Build·Artifact·Log·Security Manager…)는 이 작업장에서는 **정책 스크립트 하나 + 훅 하나 + 견본 몇 개**로 줄여 같은 효과를 낸다.

## 1. 가이드와 이 작업장의 차이
가이드는 별도 프로그램(`core/docker/…` 모듈, Docker SDK)을 만드는 것을 전제로 쓰였다. 이 작업장은 **Claude Code + bash 스크립트 + 훅**으로 돌고, 앱은 `apps/<앱>/`에 하나씩 있다. 그래서 대응은 이렇게 한다.

| 가이드 모듈 | 이 작업장에서 | 이유 |
|---|---|---|
| Docker Manager + Security Manager | **`dock.sh`**(정책 검사 뒤 실행하는 유일한 입구) + **훅**(Claude·에이전트가 `docker`를 직접 못 부르게) | 가이드 핵심 원칙 "AI는 요청, Manager가 검증 후 실행"을 훅으로 강제(guard-git과 같은 방식) |
| Environment Manager·이미지 템플릿 | `templates/docker/` — 허용 이미지 목록(버전·다이제스트 고정)과 compose 견본 | 이미지를 매번 새로 만들지 않고 재사용, 버전 고정 |
| Workspace Manager | 이미 있음: `apps/<앱>/`. 마운트는 그 앱 폴더만 | 폴더 구조를 새로 만들지 않음(가이드 14절 "중복 생성 금지") |
| Build·Artifact Manager | `apps/<앱>/artifacts/`(커밋 안 함) + 결과물이 **실제로 있고 크기·형식이 맞을 때만** 통과 | 이미 있는 "내는 것 파일 확인" 규칙과 같은 원리 |
| Log Manager | 이미 있음: `docs/test-log.txt`, guard-git의 비밀값 검사를 로그에도 | 새로 만들지 않음 |
| 병렬·직렬(FIFO) | 이미 있음: `lock.sh`의 `env:port`에 `docker:<앱>` 잠금 추가 | 같은 앱 컨테이너를 두 세션이 동시에 올리지 않게 |
| Kubernetes·Registry·CI/CD | **안 함**(가이드도 "추후") | 배포할 서버가 아직 없음. 지금 공개는 GitHub Pages(정적) |

## 2. 어디에 쓰면 이득이 큰가 (이 작업장 기준, 큰 순)
| # | 쓰는 곳 | 지금 | Docker로 | 이득 |
|---|---|---|---|---|
| ① | **DB**(Spring 백엔드의 PostgreSQL) | 각 컴퓨터에 DB 설치 필요, 연습용·운영 분리(체크리스트 16)를 손으로 | `compose.yaml`의 db 서비스 + 이름 붙은 볼륨, 테스트 전에 올리고 끝나면 내림 | 설치 0, 두 컴퓨터에서 같은 버전, 연습용 DB가 완전히 따로 |
| ② | **레드팀 공격 대상**(rt 노드) | localhost에 앱을 띄우고 공격 — SSRF 시험이 실제 내 컴퓨터·인터넷에 닿을 수 있음 | 앱을 **밖으로 나가는 네트워크 없는** 컨테이너에 가두고 공격 | 공격이 실수로 바깥에 닿지 않음 — 보안이 더 단단해짐 |
| ③ | **똑같은 테스트 환경** | Windows·Mac에 Java·Node·Playwright 브라우저를 각각 설치, 버전이 어긋날 수 있음 | Playwright 공식 이미지·JDK 이미지(버전 고정)에서 테스트 | "내 컴퓨터에선 되는데" 차단, 새 컴퓨터 준비가 Docker 설치 하나로 |
| ④ | **Android APK/AAB**(Capacitor 앱) | Android Studio·SDK를 직접 설치 | JDK + Android SDK 이미지 | 무거운 SDK 설치 없이 빌드 (Windows에서 이득 큼) |
| ⑤ | 서버 앱 배포 | 없음(정적 Pages만) | 이미지 → 서버에서 compose | **나중** — 서버가 생기면 |

**쓰지 않는 곳**: 화면 개발 중 빠른 확인(Vite 개발 서버)은 그대로 컴퓨터에서 직접(컨테이너 안은 파일 변경 감지·속도가 나쁨). 게임 엔진·Electron은 지금 만드는 앱이 없어서 보류.

## 3. Windows와 Mac에서 다른 점 (꼭 지켜야 할 것)
| 항목 | Windows | Mac |
|---|---|---|
| 설치 | Docker Desktop + WSL 2(가상화가 BIOS에서 켜져 있어야 함) | Docker Desktop(Apple 칩용) |
| 칩 | 대개 amd64 | Apple 칩이면 **arm64** → 이미지는 **amd64·arm64 둘 다** 있는 것만 허용 목록에 넣는다(Playwright·Temurin·PostgreSQL 공식 이미지는 둘 다 있음) |
| Android SDK 이미지 | 잘 됨 | Android SDK 도구 일부가 arm64 리눅스용이 없어 **느린 흉내 실행**이 되거나 안 됨 → Mac은 **Android Studio 직접** 권장 |
| iOS | 불가 | **Xcode로 직접 빌드 가능** — Docker가 아니라 Mac을 "iOS 빌드 머신"으로 쓴다(가이드 4-3과 같음) |
| 파일 속도 | 저장소가 Windows 디스크에 있으면 컨테이너에서 읽기가 느림 → 그래서 ③은 **전체를 컨테이너로 옮기지 않고 테스트 실행만** | 비교적 괜찮음 |
| 메모리 | Docker가 몇 GB를 씀 → 상한을 정함(`.wslconfig`) | Docker Desktop 설정에서 상한 |
| 라이선스 | 개인·소규모는 무료(조건은 설치 때 공식 안내 확인) | 같음 |

**찾은 기존 문제(Mac)**: 시험 스크립트가 `sed -i`를 Windows(GNU) 방식으로 써서 Mac에서 깨지던 것은 고쳤다(2026-11-23, `sedi` 함수). Mac에서 실제로 돌려 확인하는 것은 Mac 준비 때(HANDOFF 3절 7번).

## 4. 보안 정책 (`dock.sh`가 실행 전에 검사, 하나라도 어기면 실행 안 함)
가이드 9절을 그대로 강제한다.
- **허용 이미지만**: `templates/docker/images.txt`에 적힌 이미지·버전(다이제스트까지)만. `latest` 금지
- **금지 옵션**: `--privileged`, `--cap-add`, `--pid=host`, `--network=host`, Docker 소켓 마운트(`docker.sock`), `--device`, 보안 옵션 끄기
- **마운트**: 그 앱 폴더(`apps/<앱>/`)만, 저장소 밖·다른 앱·`.git`·`.claude` 금지
- **항상 붙임**: `--rm`(끝나면 지움), 메모리·CPU·프로세스 수 상한, 실행 시간 상한, root 아닌 사용자, 컨테이너 이름에 앱 이름
- **네트워크**: 기본은 그 앱 compose 안에서만. 패키지 내려받기가 필요한 단계만 바깥 허용, 레드팀 대상은 바깥 차단
- **비밀값**: 이미지·compose 파일에 쓰지 않음. `apps/<앱>/.env`(커밋 안 함)에서 실행 때만 넣음. 기존 guard-git 비밀값 검사를 compose·Dockerfile에도
- **훅**: Claude·에이전트가 `docker …`를 직접 치면 막고 "`dock.sh`로" 안내(guard-git과 같은 자리)

## 5. 그래프와 연결
- **opt(설계안)**: 앱마다 `실행 환경: docker|직접`과 DB 여부를 정한다(설계안 점수표에 "다른 컴퓨터에서 바로 됨" 항목). 사장이 ★ok-opt에서 고름
- **dd(데이터·API)**: DB가 있으면 `compose.yaml` 견본 복사 → `docs/data.md`에 "연습용 DB = 컨테이너, 운영 DB = 따로"
- **bb**: `backend.sh`가 테스트 전에 `dock.sh up apps/<앱> db` → 끝나면 내림(실패해도 내림, lock.sh `docker:<앱>`)
- **rt**: red-team이 앱을 `dock.sh up apps/<앱> --isolated`로 띄워 공격
- **sa·체크리스트**: 16번(연습용·운영 DB 분리) 근거에 compose 파일, 새 항목 후보 "Docker 정책 위반 0"
- **세션 시작 훅**: 남은 컨테이너(그 앱 이름표가 붙은 것) 목록을 알려 주고 정리 제안
- **필요한 것이 없을 때**(CLAUDE.md 규칙): Docker가 안 깔린 컴퓨터에서 docker 앱을 만나면 대신하지 않고 멈춰서 설치 방법을 알린다

## 6. 추천 진행 순서 (단계마다 시험 + 사장 검토)
| 단계 | 할 일 | Docker 없이 할 수 있나 |
|---|---|---|
| **1** | `dock.sh`(정책 검사 + 실행) + 직접 `docker` 막는 훅 + 허용 이미지 목록 + 시험. 정책 검사는 **"실행하지 않고 만들 명령만 보여 주기"** 모드로 시험 | **예** — 지금 바로 시작 가능 |
| **2** | 사장이 Windows·Mac 두 대에 Docker Desktop 설치(설치 명령·확인 순서는 HANDOFF "처음 쓰는 컴퓨터 준비"에 추가) → `docker run hello-world`·`dock.sh check`로 확인 | 사장 몫(설치·재부팅·라이선스 동의는 사장이 직접) |
| **3** | ① DB compose 견본 + backend.sh 연결 + 그래프(opt·dd·bb) | 실제 확인은 Docker 필요 |
| **4** | ② 레드팀 격리 실행 | Docker 필요 |
| **5** | ③ 테스트 환경 이미지(선택: 앱마다 `실행 환경: docker`일 때만) | Docker 필요 |
| **6** | ④ Android 빌드 이미지(Windows), Mac은 Android Studio·Xcode 직접 | 필요할 때 |
| 함께 | Mac에서 시험 스크립트가 돌게 `sed -i` 고치기 | 예 |

**하지 않는 것**: Kubernetes, 이미지 저장소(Docker Hub·GHCR), CI/CD — 배포할 서버가 생기면 그때 따로 정한다.

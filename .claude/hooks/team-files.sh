#!/usr/bin/env bash
# 개발팀 서브에이전트 파일 경계 (docs/org.md "개발팀"). backend-dev는 서버 파일만, frontend-dev는 화면 파일만 고친다.
# 둘 다 테스트·문서·state.json·HANDOFF는 못 고친다(QA팀·기획·사장 승인 영역). jq 없이 동작한다.
#
#   team-files.sh <에이전트>              : PreToolUse(Edit|Write|MultiEdit|NotebookEdit) — 에이전트 파일 frontmatter에서
#   team-files.sh                         : settings.json에서 — 입력의 agent_type이 backend-dev·frontend-dev일 때만 검사
#   team-files.sh check <앱폴더> <에이전트> [기준커밋]
#                                         : 메인 대화가 에이전트 결과를 받은 뒤 — Bash로 고친 것까지 포함해
#                                           바뀐·생긴 파일이 그 팀 소유인지 확인(어긋나면 exit 1)
#   team-files.sh owner <앱 폴더 기준 경로> : 그 파일 담당(backend|frontend|locked) 한 단어

# 앱 폴더 기준 경로 → backend | frontend | locked
owner_of() {
  local p="$1"
  case "$p" in
    *..*|"") echo locked; return ;;
  esac
  case "$p" in
    tests/*|docs/*|samples/*|state.json|HANDOFF.md|deploy.sh|.redteam-needed|*.approved*) echo locked ;;
    src/test/*) echo locked ;;   # JUnit·구조 검사(ArchitectureTest)는 QA팀 몫 — 구현 팀이 약하게 만들지 못하게
    playwright.config.*|vitest.config.*|jest.config.*) echo locked ;;   # 테스트 러너 설정도 QA팀
    src/main/java/*|src/main/kotlin/*|src/main/resources/*) echo backend ;;
    build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts|gradle.properties|gradle/*|gradlew|gradlew.bat) echo backend ;;
    pom.xml|mvnw|mvnw.cmd|.mvn/*) echo backend ;;
    *) echo frontend ;;
  esac
}

team_of() {
  case "$1" in
    backend-dev) echo backend ;;
    frontend-dev) echo frontend ;;
    *) echo "" ;;
  esac
}

# 저장소 안 어디든 "apps/<앱>/" 뒤 경로. 앱 폴더 밖이면 빈 값
app_rel() {
  local f="$1"
  case "$f" in
    apps/*/*|*/apps/*/*) printf '%s' "$f" | sed 's#^\(.*/\)\{0,1\}apps/[^/]*/##' ;;
    *) printf '' ;;
  esac
}

if [ "$1" = "owner" ]; then
  owner_of "$2"; exit 0
fi

if [ "$1" = "check" ]; then
  app="${2%/}"; agent="$3"; base="${4:-HEAD}"
  team="$(team_of "$agent")"
  if [ -z "$app" ] || [ -z "$team" ]; then
    echo "사용법: team-files.sh check apps/<앱> backend-dev|frontend-dev [기준커밋]" >&2; exit 2
  fi
  root="$(git rev-parse --show-toplevel)" || exit 2
  bad=0; n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n+1))
    rel="${f#"$app"/}"
    o="$(owner_of "$rel")"
    if [ "$o" != "$team" ]; then
      echo "경계 위반: $agent 이(가) $rel 을(를) 바꿈 (담당: $o)"; bad=1
    fi
  done < <( { git -C "$root" diff --name-only "$base" -- "$app"; git -C "$root" ls-files --others --exclude-standard -- "$app"; } | sort -u )
  if [ $bad -eq 0 ]; then echo "경계 확인: $agent 가 바꾼 파일 $n개 모두 $team 담당"; fi
  exit $bad
fi

input="$(cat)"
agent="$1"
if [ -z "$agent" ]; then
  agent="$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
team="$(team_of "$agent")"
[ -n "$team" ] || exit 0

file="$(printf '%s' "$input" | sed -n 's/.*"\(file_path\|notebook_path\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -n1 | sed 's/\\\\/\//g; s/\\/\//g')"
rel="$(app_rel "$file")"

if [ -z "$rel" ]; then
  echo "훅이 막았습니다: $agent 는 apps/<앱>/ 안의 자기 팀 파일만 고칩니다. (시도한 파일: ${file:-알 수 없음})" >&2
  exit 2
fi
o="$(owner_of "$rel")"
[ "$o" = "$team" ] && exit 0

case "$o" in
  locked) why="테스트·문서·승인 기록은 QA팀·기획·사장 몫입니다. 바꿔야 하면 고치지 말고 답에 '요청: <파일> — <이유>'로 적어 메인 대화에 넘기세요." ;;
  *) why="이 파일은 ${o} 담당입니다. 고치지 말고 답에 '요청(${o}): <파일> — <무엇을 왜>'로 적어 메인 대화(개발팀 통합)에 넘기세요." ;;
esac
echo "훅이 막았습니다: $agent 는 $team 파일만 고칩니다. (시도한 파일: $rel)
$why" >&2
exit 2

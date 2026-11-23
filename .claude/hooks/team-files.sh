#!/usr/bin/env bash
# 팀 에이전트 파일 경계 (docs/org.md). backend-dev는 서버 파일만, frontend-dev는 화면 파일만, legal은 docs/legal.md만, manager는 docs/ops.md만 고친다.
# 목록에 없는 파일은 **아무 팀도 못 고침(기본 거부)** — 테스트·문서·설정·state.json·HANDOFF·패키지 설정은 통합(메인)·QA·사장 몫.
# jq 없이 동작한다.
#
#   team-files.sh <에이전트>               : PreToolUse(Edit|Write|MultiEdit|NotebookEdit) — 에이전트 파일 frontmatter에서
#   team-files.sh                          : settings.json에서 — 입력의 agent_type이 backend-dev·frontend-dev·legal·manager일 때만 검사
#   team-files.sh mark                     : 메인이 에이전트에게 맡기기 **직전** — 저장소 전체 상태를 찍어 기준 표(<트리>:<목록>)를 출력.
#                                            표는 git 객체 해시(내용이 바뀌면 해시도 바뀜)라 에이전트가 고쳐 쓸 수 없다. 메인이 들고 있는다
#   team-files.sh check <앱폴더> <에이전트> <기준 표>
#                                          : 에이전트 답을 받은 **직후**(메인이 아무것도 쓰기 전) — 기준 뒤에 바뀐 것이
#                                            Bash로 고친 것까지 모두 그 팀 파일인지 저장소 전체에서 확인(어긋나면 exit 1)
#   team-files.sh owner <앱 폴더 기준 경로>  : 그 파일 담당(backend|frontend|locked) 한 단어

# 앱 폴더 기준 경로 → backend | frontend | locked  (대소문자 무시: Windows·Mac 파일 시스템)
owner_of() {
  local p
  p="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "/$p/" in
    *//*|*/./*|*/../*) echo locked; return ;;   # 빈 조각·. ·.. 이 든 경로는 판단하지 않고 거부
    *./*|*" /"*|*:*|*~[0-9]*) echo locked; return ;;   # Windows가 바꿔 읽는 이름(끝 점·끝 공백, a:stream, 8.3 짧은 이름 PROGRA~1)
  esac
  case "$p" in
    # 법무팀 판정서는 법무팀만
    docs/legal.md) echo legal ;;
    docs/ops.md) echo manager ;;   # 경영팀 운영 기록은 경영팀만
    # 둘 다 못 고침 — 테스트 파일은 어디에 있어도 QA팀
    *.test.*|*.spec.*|*/__tests__/*|__tests__/*|src/test/*) echo locked ;;
    # 백엔드
    src/main/java/*|src/main/kotlin/*|src/main/resources/*) echo backend ;;
    build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts|gradle.properties|gradle/*|gradlew|gradlew.bat) echo backend ;;
    pom.xml|mvnw|mvnw.cmd|.mvn/*) echo backend ;;
    # 프론트엔드 (목록에 있는 것만)
    src/main/*) echo locked ;;   # 자바 쪽 다른 폴더는 판단 보류
    src/*|public/*|index.html|android/*|ios/*) echo frontend ;;
    capacitor.config.*|tailwind.config.*|postcss.config.*|tsconfig.json|tsconfig.*.json|eslint.config.*|.eslintrc*|.prettierrc*) echo frontend ;;
    # 그 밖(tests/, docs/, package.json·잠금 파일, vite·vitest·playwright·jest 설정, .gitignore, .env*, state.json, HANDOFF.md …)
    *) echo locked ;;
  esac
}

team_of() {
  case "$1" in
    backend-dev) echo backend ;;
    frontend-dev) echo frontend ;;
    legal) echo legal ;;
    manager) echo manager ;;
    *) echo "" ;;
  esac
}

# 경로를 "C:/a/b" 꼴로 (Windows Git Bash는 cygpath, 그 밖은 그대로) + 역슬래시 → 슬래시
to_mixed() {
  local f
  f="$(printf '%s' "$1" | sed 's/\\\\/\//g; s/\\/\//g')"
  if command -v cygpath >/dev/null 2>&1 && [ -n "$f" ]; then cygpath -m -- "$f" 2>/dev/null || printf '%s' "$f"
  else printf '%s' "$f"; fi
}

repo_root() {
  local r
  r="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$r" ] || r="$CLAUDE_PROJECT_DIR"
  to_mixed "$r"
}

# 저장소 기준 경로 (저장소 밖이거나 이상한 경로면 빈 값)
repo_rel() {
  local raw f root lf lr
  raw="$(printf '%s' "$1" | sed 's/\\\\/\//g; s/\\/\//g')"
  case "/$raw/" in */../*|*/./*) printf ''; return ;; esac   # 정규화 전에 . ·.. 조각 거부
  case "${raw#[A-Za-z]:}" in *:*) printf ''; return ;; esac   # 드라이브 글자 말고 ':'가 있으면(:stream) 변환 전에 거부
  f="$(to_mixed "$raw" | sed 's#//*#/#g')"
  root="$(repo_root | sed 's#//*#/#g; s#/$##')"
  lf="$(printf '%s' "$f" | tr 'A-Z' 'a-z')"; lr="$(printf '%s' "$root" | tr 'A-Z' 'a-z')"
  case "$f" in
    /*|[A-Za-z]:*)
      [ -n "$lr" ] || { printf ''; return; }
      case "$lf" in "$lr"/*) printf '%s' "${f:$(( ${#root} + 1 ))}" ;; *) printf '' ;; esac ;;
    *) printf '%s' "$f" ;;
  esac
}

# 저장소 기준 경로 → "apps/<앱>/" 뒤 경로 (앱 폴더 밖이면 빈 값). 맨 앞 apps/<앱>/ 만 벗긴다
app_rel() {
  local r="$1"
  case "$r" in
    apps/*/*) printf '%s' "$r" | sed 's#^apps/[^/]*/##' ;;
    *) printf '' ;;
  esac
}

if [ "$1" = "owner" ]; then
  owner_of "$2"; exit 0
fi

# ---- mark / check: 저장소 전체를 임시 인덱스로 찍어 비교 (실제 index·작업 폴더는 그대로) ----
snap_tree() {
  local idx t
  idx="$(mktemp)"
  GIT_INDEX_FILE="$idx" git read-tree HEAD 2>/dev/null || { rm -f "$idx"; return 1; }
  GIT_INDEX_FILE="$idx" git add -A . >/dev/null 2>&1 || { rm -f "$idx"; return 1; }
  t="$(GIT_INDEX_FILE="$idx" git write-tree)"; rm -f "$idx"; printf '%s' "$t"
}
# 빌드 결과물 폴더 이름 — 이 폴더는 "있음/없음"만 보고 안의 내용은 보지 않는다(설치·빌드 때마다 바뀜)
is_build_dir() {
  case "$1" in
    */node_modules/|node_modules/|*/build/|build/|*/dist/|dist/|*/.gradle/|.gradle/|*/target/|target/|*/out/|*/coverage/|*/test-results/|*/playwright-report/|*/.vite/) return 0 ;;
  esac
  return 1
}
# .gitignore로 빠진 것과 git 설정의 지문. 줄마다:
#   D <폴더>        빌드 결과물 폴더(있음만)
#   F <파일> <해시>  그 밖의 무시 파일
#   T <폴더> <해시>  그 밖의 무시 폴더 — 안의 파일 전부(개수 제한 없음)의 경로·내용을 합친 해시
#   G <이름> <해시>  git 설정: config·config.worktree·info/*·hooks/* 내용(공용 git 폴더 포함), `git config --list` 전체(전역·시스템 포함)
# 남은 위험(사장 확인한 선택): 빌드 결과물 폴더(node_modules 등)는 수만 개라 내용을 해시하지 않는다.
dir_hash() { # 폴더 안 모든 항목(파일·폴더·바로가기)의 "종류·권한·경로·내용(바로가기는 가리키는 곳)" 목록 → 한 해시
  local d="$1" f m
  find "$d" -mindepth 1 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    m="$(ls -ld -- "$f" 2>/dev/null | cut -c1-10)"   # 종류+권한(실행 권한 포함) 예: -rwxr-xr-x, lrwxrwxrwx
    if [ -L "$f" ]; then printf '%s %s -> %s\n' "$m" "$f" "$(readlink -- "$f")"
    elif [ -f "$f" ]; then printf '%s %s %s\n' "$m" "$f" "$(git hash-object -- "$f")"
    else printf '%s %s\n' "$m" "$f"; fi
  done | git hash-object --stdin
}
snap_ignored() {
  local e d f
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      */) if is_build_dir "$e"; then echo "D $e"; else echo "T $e $(dir_hash "$e")"; fi ;;
      *) echo "F $e $(git hash-object -- "$e")" ;;
    esac
  done < <(git ls-files --others --ignored --exclude-standard --directory 2>/dev/null)
  for d in "$(git rev-parse --git-dir)" "$(git rev-parse --git-common-dir)"; do
    for f in config config.worktree; do [ -f "$d/$f" ] && echo "G $d/$f $(git hash-object -- "$d/$f")"; done
    [ -d "$d/info" ] && echo "G $d/info $(dir_hash "$d/info")"
    [ -d "$d/hooks" ] && echo "G $d/hooks $(dir_hash "$d/hooks")"
  done | sort -u
  echo "G config-list $(git config --show-origin --list 2>/dev/null | git hash-object --stdin)"
}

if [ "$1" = "mark" ] || [ "$1" = "check" ]; then
  root="$(git rev-parse --show-toplevel)" || exit 2
  cd "$root" || exit 2
  if [ "$1" = "mark" ]; then
    t="$(snap_tree)" || { echo "기준점을 찍지 못했습니다." >&2; exit 2; }
    b="$(snap_ignored | sort | git hash-object -w --stdin)" || exit 2
    echo "$t:$b"; exit 0
  fi
  app="${2%/}"; agent="$3"; token="$4"
  team="$(team_of "$agent")"
  case "$app" in apps/*) ;; *) app="" ;; esac
  case "$app" in */*/*|*..*) app="" ;; esac
  base="${token%%:*}"; blob="${token#*:}"
  if [ -z "$app" ] || [ -z "$team" ] || [ -z "$token" ] || [ "$base" = "$token" ]; then
    echo "사용법: team-files.sh check apps/<앱> backend-dev|frontend-dev|legal <기준 표>  (기준 표 = 맡기기 직전 team-files.sh mark 의 출력)" >&2; exit 2
  fi
  [ "$(git cat-file -t "$base" 2>/dev/null)" = "tree" ] && [ "$(git cat-file -t "$blob" 2>/dev/null)" = "blob" ] \
    || { echo "기준 표가 올바르지 않습니다: $token" >&2; exit 2; }
  now="$(snap_tree)" || exit 2
  bad=0; n=0
  # 이름 바꾸기 감지를 끄고 지운 쪽·생긴 쪽을 모두 본다(잠긴 파일을 옮겨 숨기기 차단)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n+1))
    rel="$(app_rel "$f")"
    case "$f" in "$app"/*) ;; *) rel="" ;; esac
    if [ -z "$rel" ]; then echo "경계 위반: $agent 이(가) 앱 폴더 밖 $f 을(를) 바꿈"; bad=1; continue; fi
    o="$(owner_of "$rel")"
    [ "$o" = "$team" ] || { echo "경계 위반: $agent 이(가) $f 을(를) 바꿈 (담당: $o)"; bad=1; }
  done < <(git diff --no-renames --name-only "$base" "$now")
  # .gitignore로 숨긴 파일의 생김·바뀜·지움, git 설정 변경. 앱 폴더 안 빌드 결과물 폴더가 새로 생긴 것만 허용
  while IFS= read -r l; do
    case "$l" in
      "D $app"/*) ;;
      G\ *) echo "경계 위반: $agent 이(가) git 설정을 바꿈 — ${l#G }"; bad=1 ;;
      *) echo "경계 위반: $agent 이(가) .gitignore로 빠진 것을 바꿈 — ${l#? }"; bad=1 ;;
    esac
  done < <(comm -3 <(git cat-file blob "$blob" | sort) <(snap_ignored | sort) | sed 's/^[[:space:]]*//; s/ [0-9a-f]\{40,64\}$//' | sort -u)
  if [ $bad -eq 0 ]; then echo "경계 확인: $agent 가 바꾼 파일 $n개 모두 $team 담당"; fi
  exit $bad
fi

# ---- 훅 ----
input="$(cat)"
agent="$1"
if [ -z "$agent" ]; then
  agent="$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
team="$(team_of "$agent")"
[ -n "$team" ] || exit 0

file="$(printf '%s' "$input" | sed -n 's/.*"\(file_path\|notebook_path\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -n1)"
rel="$(app_rel "$(repo_rel "$file")")"

if [ -z "$rel" ]; then
  echo "훅이 막았습니다: $agent 는 이 저장소 apps/<앱>/ 안의 자기 팀 파일만 고칩니다. (시도한 파일: ${file:-알 수 없음})" >&2
  exit 2
fi
o="$(owner_of "$rel")"
[ "$o" = "$team" ] && exit 0

case "$o" in
  locked) why="테스트·문서·설정(package.json·vite/테스트 설정·.gitignore 등)·승인 기록은 통합(메인)·QA팀·기획·사장 몫입니다. 바꿔야 하면 고치지 말고 답에 '요청(통합|qa): <파일> — <무엇을 왜>'로 적어 넘기세요." ;;
  *) why="이 파일은 ${o} 담당입니다. 고치지 말고 답에 '요청(${o}): <파일> — <무엇을 왜>'로 적어 메인 대화(개발팀 통합)에 넘기세요." ;;
esac
echo "훅이 막았습니다: $agent 는 $team 파일만 고칩니다. (시도한 파일: $rel)
$why" >&2
exit 2

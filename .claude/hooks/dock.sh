#!/usr/bin/env bash
# Docker로 가는 유일한 입구 (docs/docker-review.md). Claude·에이전트는 docker를 직접 부르지 않고(guard-docker.sh가 막음)
# 이 스크립트에 "무엇을 하고 싶은지"만 요청한다. 이 스크립트가 정책을 검사하고, 통과한 것만 docker에 넘긴다.
# Windows(Git Bash)·Mac 둘 다. jq 없이.
#
#   dock.sh check                         Docker·Compose가 있고 돌아가는지, 칩(amd64/arm64). 없으면 3(설치 안내)
#   dock.sh pin [별명…]                   허용 목록 이미지의 다이제스트를 실제로 조회해 고정(amd64·arm64 둘 다 있어야)
#   dock.sh run apps/<앱> <별명> [옵션] -- <명령…>
#        옵션: --net none|out (기본 none = 네트워크 없음, out = 패키지 받기처럼 바깥이 꼭 필요할 때만)
#              --mem 2g (최대 6g) · --cpus 2 (최대 4) · --time 900초 (최대 3600)
#              --port <내 컴퓨터 포트>:<컨테이너 포트> (127.0.0.1에만, 여러 번 가능 — 그 포트 잠금도 잡음)
#              --env (앱 폴더 .env를 실행 때만 넣음, 이미지엔 안 남음) · --writable (컨테이너 안 파일 시스템 쓰기 허용)
#   dock.sh up apps/<앱> [서비스…]        apps/<앱>/compose.yaml 검사 후 띄움(프로젝트 이름 ai-<앱>)
#   dock.sh down apps/<앱>                내림(데이터 볼륨은 지우지 않음 — 지우기는 사장이 직접)
#   dock.sh ps [apps/<앱>] · dock.sh clean [apps/<앱>]   이 작업장이 띄운 컨테이너(이름표 ai-workflow.app) 보기·지우기
#   어느 명령이든 맨 앞에 --dry-run 을 주면 docker를 부르지 않고 만들 명령만 보여 준다(시험·확인용)
# 끝 코드: 0 성공 / 1 실행 실패 / 2 정책 위반·사용법 / 3 Docker 없음 / 4 시간 초과·잠금 대기 초과

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || { echo "dock.sh: git 저장소 안에서 실행하세요." >&2; exit 2; }
IMAGES="$ROOT/.claude/skills/build-app/templates/docker/images.txt"   # 위치 고정(환경 변수로 바꿀 수 없음)
LOCKSH="$HERE/lock.sh"
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'   # Windows Git Bash가 /workspace 같은 경로를 바꿔 버리지 않게

DRY=0; [ "$1" = "--dry-run" ] && { DRY=1; shift; }
die() { local c="$1"; shift; echo "dock.sh: $*" >&2; exit "$c"; }
deny() { die 2 "정책 위반 — $*"; }
show() { printf '%q ' "$@"; echo; }
dk() { if [ $DRY = 1 ]; then printf '[미리보기] '; show docker "$@"; return 0; fi; docker "$@"; }

need_docker() {
  [ $DRY = 1 ] && return 0
  command -v docker >/dev/null 2>&1 || die 3 "Docker가 없습니다. 설치: Windows — Docker Desktop(WSL 2 엔진), Mac — Docker Desktop(Apple 칩용). 설치 뒤 'bash .claude/hooks/dock.sh check'. (docs/docker-review.md 6절 2단계)"
  docker info >/dev/null 2>&1 || die 3 "Docker가 깔려 있지만 돌고 있지 않습니다. Docker Desktop을 켠 뒤 다시."
}

# ---- 허용 목록 ----
img_line() { awk -v a="$1" '!/^#/ && NF>=4 && $1==a { print; exit }' "$IMAGES"; }
img_ref()  { img_line "$1" | awk '{ print $2 }'; }
img_dig()  { img_line "$1" | awk '{ print $3 }'; }
img_user() { img_line "$1" | awk '{ print $4 }'; }
allowed_full() { awk '!/^#/ && NF>=4 && $3 ~ /^sha256:[0-9a-f]{64}$/ { print $2 "@" $3 }' "$IMAGES"; }

# ---- compose 검사 (yq·jq 없이 awk) ----
# 원본 compose.yaml: 맨 위는 services·volumes, 서비스 설정은 아래 목록만, 이름 붙은 볼륨은 이름만(driver_opts로 내 폴더 연결 막기).
# 흐름 문법({ } [ ] — ${변수}는 제외)·따옴표 붙은 키·탭·type:/source:(긴 볼륨 문법) 줄은 거부. 문제마다 한 줄.
src_check() {
  awk -v q="'" '
  BEGIN { oksvc=" image environment ports volumes healthcheck mem_limit cpus pids_limit security_opt depends_on command working_dir read_only tmpfs expose labels "; oktop=" services volumes " }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  /\t/ { print NR "번째 줄: 탭 문자"; next }
  {
    s = $0; gsub(/\$\{[A-Za-z0-9_:?+=-]*\}/, "", s); sub(/[[:space:]]+#.*$/, "", s)
    if (s ~ /[][{}]/) print NR "번째 줄: 흐름 문법({ } [ ]) 대신 줄 바꿈 목록으로"
    if (s ~ /^[[:space:]]*(-[[:space:]]*)?"[^"]*"[[:space:]]*:/ || s ~ ("^[[:space:]]*(-[[:space:]]*)?" q "[^" q "]*" q "[[:space:]]*:")) print NR "번째 줄: 따옴표 붙은 키"
    if (s ~ /^[[:space:]]*(-[[:space:]]*)?(type|source)[[:space:]]*:/) print NR "번째 줄: type:/source:(긴 볼륨 문법) 대신 \"이름:/경로\" 꼴로"
    if (s ~ /^[[:space:]]*(-[[:space:]]*)?\?/) print NR "번째 줄: ? 로 시작하는 키(명시적 키 문법)"
    if (s ~ /^ *[A-Za-z0-9_.-]+[[:space:]]*:([[:space:]]|$)/) {
      match(s, /^ */); ind = RLENGTH; key = substr(s, ind + 1); sub(/[[:space:]]*:.*/, "", key)
      while (n > 0 && st[n] >= ind) n--
      if (n == 0) top = key
      if (n == 0 && index(oktop, " " key " ") == 0) print NR "번째 줄: 맨 위에 허용 안 된 설정 " key
      if (n == 1 && key !~ /^[a-z0-9][a-z0-9_-]*$/) print NR "번째 줄: 서비스·볼륨 이름은 영문 소문자·숫자·_·- 만(" key ")"
      if (n == 2 && top == "services" && index(oksvc, " " key " ") == 0) print NR "번째 줄: 서비스에 허용 안 된 설정 " key
      if (n == 2 && top == "volumes") print NR "번째 줄: 이름 붙은 볼륨은 이름만(" key " 금지)"
      st[++n] = ind
    }
  }' "$1"
}
# 블록 문법 YAML(docker compose config 출력)을 "경로<탭>값" 줄로 편다. 예: services.db.ports[0].host_ip	127.0.0.1
# 모르는 꼴은 !PARSE, 빈 것이 아닌 흐름 문법은 !FLOW 로 내보내 거부되게 한다(모르면 막기).
yaml_flat() {
  awk -v q="'" '
  function unq(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
    if (v ~ /^".*"$/ || v ~ ("^" q ".*" q "$")) v = substr(v, 2, length(v) - 2); return v }
  function path(  p, i) { p = ""; for (i = 1; i <= n; i++) p = p ((i > 1 && nm[i] !~ /^\[/) ? "." : "") nm[i]; return p }
  function popto(i, item) { while (n > 0 && (ix[n] > i || (ix[n] == i && (!item || nm[n] ~ /^\[/)))) n-- }
  function keyline(s, i,   k, v) {
    if (!match(s, /^("[^"]*"|[^:"[:space:]][^:"]*):( |$)/)) { print "!PARSE\t" s; return }
    k = unq(substr(s, 1, RLENGTH - (substr(s, RLENGTH, 1) == " " ? 2 : 1))); v = unq(substr(s, RLENGTH + 1))
    popto(i, 0)
    # 맨 위·서비스 이름·서비스 설정 자리(깊이 0~2)의 키에 점·괄호가 있으면 경로가 섞인다(서비스 "db.x" + privileged → db 의 x 처럼 보임) → 거부
    if (n < 3 && k !~ /^[A-Za-z0-9_-]+$/) { print "!KEY\t" k; return }
    if (v == "") { nm[++n] = k; ix[n] = i; return }
    if (v ~ /^[|>][-+]?[0-9]?$/) { print path() (n ? "." : "") k "\t(block)"; blk = i; return }
    if (v ~ /^[[{]/ && v != "{}" && v != "[]") { print "!FLOW\t" path() "." k; return }
    print path() (n ? "." : "") k "\t" v
  }
  BEGIN { blk = -1 }
  {
    match($0, /^ */); i = RLENGTH; s = substr($0, i + 1)
    if (blk >= 0) { if (s == "" || i > blk) next; blk = -1 }
    if (s == "" || s ~ /^#/) next
    if (s ~ /^(-[[:space:]]+)?\?/) { print "!PARSE\t" s; next }   # ? 명시적 키 문법은 읽지 않음
    if (s ~ /^-( |$)/) {
      popto(i, 1); p = path(); idx = c[p]++
      nm[++n] = "[" idx "]"; ix[n] = i
      r = s; sub(/^-[[:space:]]*/, "", r)
      if (r == "") next
      if (r ~ /^("[^"]*"|[^:"[:space:]][^:"]*):( |$)/) { keyline(r, i + 2) }
      else { n--; v = unq(r); if (v ~ /^[[{]/ && v != "{}" && v != "[]") print "!FLOW\t" p; else print p "[" idx "]\t" v }
      next
    }
    keyline(s, i)
  }'
}
# 편 결과를 검사. 문제는 한 줄씩, bind 볼륨 원본은 "BIND<탭>경로"로 내보내 셸이 실제 위치를 따라가 본다.
resolved_check() {
  awk -F'\t' -v allow="$(allowed_full)" '
  BEGIN { al = "\n" allow "\n"
    # 금지 목록이 아니라 허용 목록: 원본 허용 설정(src_check oksvc) + compose가 붙이는 networks. 모르는 설정은 다 거부(모르면 막기)
    oksvc = " image environment ports volumes healthcheck mem_limit cpus pids_limit security_opt depends_on command working_dir read_only tmpfs expose labels networks "
  }
  /^!/ { print "해석 결과를 읽지 못함(" $1 " " $2 ")"; next }
  {
    p = $1; v = $2; top = p; sub(/[.[].*/, "", top)
    if (top !~ /^(name|services|volumes|networks)$/) { print "맨 위에 허용 안 된 설정: " top; next }
    if (top == "volumes" || top == "networks") {
      if (p ~ /^(volumes|networks)\.[^.]+$/) next
      k = p; sub(/^[^.]+\.[^.]+\./, "", k); if (k != "name") print top " 설정은 이름만(" p ")"; next }
    if (top != "services") next
    if (!match(p, /^services\.[^.[]+/)) { print "이상한 서비스 경로: " p; next }
    svc = substr(p, 1, RLENGTH); rest = substr(p, RLENGTH + 2); key = rest; sub(/[.[].*/, "", key)
    seen[svc] = 1
    if (svc !~ /^services\.[a-z0-9][a-z0-9_-]*$/) { print "서비스 이름이 이상함: " svc; next }
    if (index(oksvc, " " key " ") == 0) { print svc ": 허용 안 된 설정 " key; next }
    if (key == "image") { img[svc] = 1; if (index(al, "\n" v "\n") == 0) print svc ": 허용 목록과 다른 이미지 " v }
    if (key == "user" && (v ~ /^(root|0)(:.*)?$/)) print svc ": root로 실행"
    if (key == "security_opt" && v !~ /^no-new-privileges([:=]true)?$/) print svc ": security_opt 는 no-new-privileges 만 (" v ")"
    if (match(rest, /^ports\[[0-9]+\]/)) { pi = svc "." substr(rest, 1, RLENGTH); port[pi] = 1; if (rest ~ /\.host_ip$/ && v == "127.0.0.1") lo[pi] = 1 }
    if (match(rest, /^volumes\[[0-9]+\]/)) { vi = svc "." substr(rest, 1, RLENGTH); vol[vi] = 1
      if (rest ~ /\]\.type$/) { vt[vi] = v; if (v !~ /^(volume|bind|tmpfs)$/) print vi ": 볼륨 종류 " v " 금지" }
      if (rest ~ /\]\.source$/) vs[vi] = v }
  }
  END {
    for (s in seen) if (!(s in img)) print s ": image 없음"
    for (x in port) if (!(x in lo)) print x ": 포트는 127.0.0.1 에만"
    for (x in vol) { if (!(x in vt)) print x ": 볼륨 종류를 알 수 없음"
      else if (vt[x] == "bind") { if (vs[x] == "") print x ": bind 원본 없음"; else print "BIND\t" vs[x] } }
  }'
}

# ---- 앱 폴더 ----
app_dir() { # apps/<앱> → 확인된 앱 이름
  local a="${1%/}"; a="${a#apps/}"
  printf '%s' "$a" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || deny "앱 이름은 영문 소문자·숫자·하이픈만: $1"
  [ -d "$ROOT/apps/$a" ] || deny "앱 폴더가 없습니다: apps/$a"
  APP="$a"; app_safe
  # Windows: docker에 넘길 경로는 C:/… 꼴
  if (cd "$APPABS" && pwd -W) >/dev/null 2>&1; then APPHOST="$(cd "$APPABS" && pwd -W)"; else APPHOST="$APPABS"; fi
}
# 앱 폴더가 정말 저장소 apps/<앱> 인지 + 안쪽에 밖을 가리키는 바로가기가 없는지. app_dir 때와 docker 실행 바로 직전에 두 번 본다.
app_safe() {
  local a="$APP" rroot real
  [ -L "$ROOT/apps" ] && deny "apps/ 폴더 자체가 바로가기(symlink)입니다 — 다른 곳을 연결할 수 있어 거부"
  [ -L "$ROOT/apps/$a" ] && deny "앱 폴더가 바로가기(symlink)입니다 — 다른 곳을 연결할 수 있어 거부: apps/$a"
  # 실제 경로(바로가기를 따라간 끝)가 저장소의 실제 위치 + /apps/<앱> 이어야
  rroot="$(cd "$ROOT" && pwd -P)"; real="$(cd "$ROOT/apps/$a" 2>/dev/null && pwd -P)"
  [ -n "$real" ] && [ "$real" = "$rroot/apps/$a" ] || deny "앱 폴더의 실제 위치가 저장소 apps/ 밖입니다: ${real:-알 수 없음}"
  APPABS="$real"
  # 안쪽 바로가기: 앱 폴더 안을 가리키면 괜찮다(node_modules/.bin 등). 밖·없는 곳을 가리키면 거부(compose ./볼륨·.env·compose.yaml이
  # 내 컴퓨터의 다른 곳을 열 수 있음). Git Bash는 NTFS 정션도 바로가기로 보이고, Windows는 dir /AL 로 한 번 더 찾는다.
  local links l t
  links="$(find "$APPABS" -type l 2>/dev/null)"
  if command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    links="$links
$(MSYS2_ARG_CONV_EXCL='*' cmd /c dir /AL /S /B "$(cygpath -w "$APPABS")" 2>/dev/null | tr -d '\r' | grep -E '^[A-Za-z]:\\' | while IFS= read -r l; do cygpath -u "$l"; done)"
  fi
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    t="$(readlink -f -- "$l" 2>/dev/null)"
    case "$t/" in "$APPABS"/*) ;; *) deny "앱 폴더 안에 밖(또는 없는 곳)을 가리키는 바로가기·정션이 있습니다: ${l#"$APPABS"/} → ${t:-?} — 지우거나 실제 파일로 바꾸세요" ;; esac
  done <<< "$links"
}

cmd="$1"; shift 2>/dev/null
case "$cmd" in
check)
  if [ $DRY = 1 ]; then dk version; dk compose version; exit 0; fi
  command -v docker >/dev/null 2>&1 || die 3 "Docker가 없습니다. 설치: Windows — Docker Desktop(WSL 2 엔진, BIOS 가상화 켜짐 필요), Mac — Docker Desktop(Apple 칩이면 Apple Silicon용). 라이선스는 설치 때 공식 안내 확인."
  sv="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" || die 3 "Docker 엔진이 돌고 있지 않습니다. Docker Desktop을 켜세요."
  cv="$(docker compose version --short 2>/dev/null)" || die 3 "Docker Compose가 없습니다(Docker Desktop에 함께 들어 있음)."
  ar="$(docker info --format '{{.Architecture}}' 2>/dev/null)"
  unp="$(awk '!/^#/ && NF>=4 && $3=="-" { print $1 }' "$IMAGES" | paste -sd, -)"
  echo "Docker 엔진 $sv · Compose $cv · 칩 $ar${unp:+ · 아직 고정 안 된 이미지: $unp (bash .claude/hooks/dock.sh pin)}"
  exit 0 ;;

pin)
  need_docker
  aliases="${*:-$(awk '!/^#/ && NF>=4 { print $1 }' "$IMAGES")}"
  for a in $aliases; do
    ref="$(img_ref "$a")"; [ -n "$ref" ] || deny "허용 목록에 없는 별명: $a"
    case "$ref" in *:latest|*[!:]) printf '%s' "$ref" | grep -q ':' || deny "$a: 태그가 없습니다($ref) — 버전 태그를 적으세요"; ;; esac
    printf '%s' "$ref" | grep -q ':latest$' && deny "$a: latest 태그는 쓰지 않습니다"
    if [ $DRY = 1 ]; then dk buildx imagetools inspect "$ref" --format '{{.Manifest}}'; continue; fi
    out="$(docker buildx imagetools inspect "$ref" --format '{{.Manifest}}' 2>&1)" || die 1 "$a: 이미지 정보를 못 받았습니다(인터넷·이름 확인): $(printf '%s' "$out" | tail -n1)"
    dg="$(printf '%s\n' "$out" | sed -n 's/^Digest:[[:space:]]*\(sha256:[0-9a-f]\{64\}\).*/\1/p' | head -n1)"
    [ -n "$dg" ] || die 1 "$a: 다이제스트를 읽지 못했습니다."
    for p in linux/amd64 linux/arm64; do
      printf '%s\n' "$out" | grep -Eq "^[[:space:]]*Platform:[[:space:]]*$p\$" || deny "$a($ref): $p 판이 없습니다 — Windows·Mac 둘 다 쓰려면 두 칩 모두 있어야 합니다"
    done
    awk -v a="$a" -v d="$dg" 'BEGIN{OFS="  "} !/^#/ && NF>=4 && $1==a { $3=d } { print }' "$IMAGES" > "$IMAGES.t" && mv "$IMAGES.t" "$IMAGES"
    echo "고정: $a = $ref@$dg (amd64·arm64)"
  done
  echo "허용 목록이 바뀌었으면 커밋하세요(두 컴퓨터가 같은 이미지를 쓰게)."
  exit 0 ;;

run)
  app_dir "$1"; shift
  alias="$1"; shift
  [ -n "$alias" ] && [ -n "$(img_line "$alias")" ] || deny "허용 목록에 없는 이미지 별명: ${alias:-없음} (목록: $IMAGES)"
  dg="$(img_dig "$alias")"
  printf '%s' "$dg" | grep -Eq '^sha256:[0-9a-f]{64}$' || deny "$alias 이미지가 아직 고정되지 않았습니다 — 'bash .claude/hooks/dock.sh pin $alias' 먼저(사장 컴퓨터에 Docker가 있어야)"
  user="$(img_user "$alias")"; [ "$user" = "-" ] && deny "$alias 는 compose 서비스용입니다(dock.sh up)."
  case "$user" in root|0|0:*) deny "$alias: root로 실행하지 않습니다." ;; esac
  net=none; mem=2g; cpus=2; tmo=900; envf=0; ro=1; ports=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --net) case "$2" in none) net=none ;; out) net=bridge ;; *) deny "--net 은 none 또는 out 만" ;; esac; shift 2 ;;
      --mem) printf '%s' "$2" | grep -Eq '^[1-6]g$|^[1-9][0-9]{2,3}m$' || deny "--mem 은 128m~6g"; mem="$2"; shift 2 ;;
      --cpus) printf '%s' "$2" | grep -Eq '^[1-4](\.[0-9])?$' || deny "--cpus 는 1~4"; cpus="$2"; shift 2 ;;
      --time) printf '%s' "$2" | grep -Eq '^[0-9]+$' && [ "$2" -ge 10 ] && [ "$2" -le 3600 ] || deny "--time 은 10~3600초"; tmo="$2"; shift 2 ;;
      --port) printf '%s' "$2" | grep -Eq '^[0-9]{2,5}:[0-9]{2,5}$' || deny "--port 는 <내 포트>:<컨테이너 포트> 숫자만(주소는 127.0.0.1로 고정)"; ports+=("$2"); shift 2 ;;
      --env) envf=1; shift ;;
      --writable) ro=0; shift ;;
      --) shift; break ;;
      *) deny "모르는 옵션: $1 (docker 옵션을 직접 넘길 수 없습니다)" ;;
    esac
  done
  [ $# -gt 0 ] || deny "실행할 명령이 없습니다: dock.sh run apps/$APP $alias -- <명령…>"
  name="ai-$APP-$alias-$$"
  args=(run --rm --init --name "$name" --label "ai-workflow.app=$APP" --label "ai-workflow.image=$alias"
        --cap-drop ALL --security-opt no-new-privileges --pids-limit 512
        --memory "$mem" --memory-swap "$mem" --cpus "$cpus" --network "$net"
        --user "$user" -e HOME=/tmp --tmpfs /tmp:rw,size=512m
        -v "$APPHOST:/workspace" -w /workspace)
  [ $ro = 1 ] && args+=(--read-only)
  if [ $envf = 1 ]; then
    [ -f "$APPABS/.env" ] || deny "--env 인데 apps/$APP/.env 가 없습니다(.env.example 참고, 커밋 안 함)"
    args+=(--env-file "$APPHOST/.env")
  fi
  locks=""
  for p in "${ports[@]}"; do
    [ "$net" = none ] && deny "--port 를 쓰려면 --net out (포트를 열려면 네트워크가 필요)"
    args+=(-p "127.0.0.1:$p"); locks="${locks:+$locks,}env:port:${p%%:*}"
  done
  args+=("$(img_ref "$alias")@$dg" "$@")   # 이름:태그@다이제스트 (다이제스트가 우선 — 태그는 사람이 읽기용)
  if [ $DRY = 1 ]; then printf '[미리보기]%s ' "${locks:+ (잠금 $locks)}"; show docker "${args[@]}"; exit 0; fi
  need_docker
  app_safe   # 실행 바로 직전에 한 번 더(그 사이 바로가기로 바꿔치기 막기)
  runit() {
    docker "${args[@]}" & local dp=$!
    ( sleep "$tmo"; docker kill "$name" >/dev/null 2>&1 && echo "dock.sh: ${tmo}초 시간 초과로 멈춤 ($name)" >&2 ) & local wp=$!
    wait "$dp"; local rc=$?
    kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
    return $rc
  }
  if [ -n "$locks" ] && [ -f "$LOCKSH" ]; then
    export -f runit 2>/dev/null
    bash "$LOCKSH" run "$locks" --label "dock.sh $APP $alias" -- bash -c "$(declare -f runit); $(declare -p args name tmo); runit"
  else
    runit
  fi
  exit $? ;;

up|down)
  app_dir "$1"; shift
  f="$APPABS/compose.yaml"; [ -f "$f" ] || deny "apps/$APP/compose.yaml 이 없습니다(견본: .claude/skills/build-app/templates/docker/)"
  if [ "$cmd" = up ]; then
    bad=""
    # 줄 단위 검사(yq 없이). 복잡한 YAML(앵커·병합·여러 문서)은 숨은 설정을 못 보므로 거부
    grep -nE '^[[:space:]]*<<:|[&*][A-Za-z_][A-Za-z0-9_-]*([[:space:]]|$)|^---' "$f" | grep -v '^[0-9]*:[[:space:]]*#' | head -n3 | grep -q . && bad="$bad YAML 앵커·병합·여러 문서는 쓰지 않음;"
    grep -nE '^[[:space:]]*(privileged|cap_add|devices|device_cgroup_rules|pid|ipc|network_mode|userns_mode|cgroup_parent|sysctls|build|extends|include)[[:space:]]*:' "$f" | grep -q . && bad="$bad 금지된 설정(privileged·cap_add·devices·pid·ipc·network_mode·userns_mode·sysctls·build·extends·include);"
    grep -nE 'docker\.sock|docker_engine|/proc|/sys([/:]|$)' "$f" | grep -q . && bad="$bad Docker 소켓·호스트 시스템 경로 연결;"
    grep -nE 'unconfined|seccomp|apparmor|label[[:space:]]*:?[[:space:]]*disable' "$f" | grep -q . && bad="$bad 보안 옵션 끄기;"
    # 이미지: 허용 목록의 이름@다이제스트와 글자 그대로 같아야
    allow="$(allowed_full)"
    while IFS= read -r im; do
      [ -n "$im" ] || continue
      printf '%s\n' "$allow" | grep -qxF -- "$im" || bad="$bad 허용 목록에 없는(또는 고정 안 된) 이미지: $im;"
    done < <(sed -n 's/^[[:space:]]*image:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"' ]*\).*/\1/p' "$f")
    grep -qE '^[[:space:]]*image:' "$f" || bad="$bad image: 가 하나도 없음;"
    # 포트: 127.0.0.1 에만
    while IFS= read -r p; do
      printf '%s' "$p" | grep -Eq '^"?127\.0\.0\.1:[0-9]{2,5}:[0-9]{2,5}"?$' || bad="$bad 포트는 \"127.0.0.1:<내 포트>:<컨테이너 포트>\" 꼴만: $p;"
    done < <(awk '/^[[:space:]]*ports:/{f=1; next} f && /^[[:space:]]*-/{ sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next } f && !/^[[:space:]]*-/{ f=0 }' "$f")
    # 볼륨: 이름 붙은 볼륨(이름:/경로) 또는 앱 폴더 안 ./경로 만
    while IFS= read -r v; do
      src="${v%%:*}"; src="${src#\"}"; src="${src#\'}"
      case "$src" in
        ./*) printf '%s' "$src" | grep -q '\.\.' && bad="$bad 볼륨이 앱 폴더 밖을 가리킴: $v;" ;;
        [a-z0-9]*) printf '%s' "$src" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' || bad="$bad 이상한 볼륨: $v;" ;;
        *) bad="$bad 볼륨은 이름 붙은 볼륨이나 ./앱 폴더 안 경로만: $v;" ;;
      esac
    done < <(awk '/^[[:space:]]+volumes:/{f=1; next} f && /^[[:space:]]+-/{ sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next } f && !/^[[:space:]]+-/{ f=0 }' "$f")
    # 비밀값: 비밀번호·키 값은 ${변수}(앱 폴더 .env, 커밋 안 함)로만
    grep -nE '^[[:space:]]*-?[[:space:]]*[A-Z0-9_]*(PASSWORD|PASSWD|SECRET|TOKEN|API_KEY|PRIVATE_KEY)[A-Z0-9_]*[[:space:]]*[:=][[:space:]]*[^$[:space:]]' "$f" | grep -q . && bad="$bad 비밀값을 파일에 직접 씀(\${변수}로, 값은 apps/$APP/.env);"
    # 원본 파일: 허용된 설정 이름만, 흐름 문법·따옴표 키·긴 볼륨 문법 금지(숨은 설정을 줄 검사가 못 보는 길을 닫음)
    sb="$(src_check "$f" | head -n 5 | paste -sd';' -)"; [ -n "$sb" ] && bad="$bad $sb;"
    [ -z "$bad" ] || deny "compose.yaml 검사 실패:$bad"
    for s in "$@"; do printf '%s' "$s" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' || deny "서비스 이름만 넘길 수 있습니다: $s"; done
    envarg=(); [ -f "$APPABS/.env" ] && envarg=(--env-file "$APPHOST/.env")
    if [ $DRY = 1 ]; then
      dk compose -p "ai-$APP" -f "$APPHOST/compose.yaml" "${envarg[@]}" config
      echo "[미리보기] (위 해석 결과를 검사한 뒤, 그 결과 그대로를 표준 입력으로)"
      dk compose -p "ai-$APP" --project-directory "$APPHOST" -f - up -d --wait "$@"
      exit 0
    fi
    need_docker
    app_safe
    # Docker가 해석한 결과(변수·짧은 문법·상대 경로를 다 푼 것)를 검사하고, 검사한 그 글자 그대로 띄운다(검사 뒤 파일 바꿔치기 막기)
    resolved="$(docker compose -p "ai-$APP" -f "$APPHOST/compose.yaml" "${envarg[@]}" config 2>/dev/null)" \
      || die 1 "compose.yaml 해석 실패 — 'docker compose config' 오류(문법·변수 확인)"
    rb="$(printf '%s\n' "$resolved" | yaml_flat | resolved_check)"
    # bind 원본: 있어야 하고, 실제 위치가 앱 안이고, 앱 폴더까지 올라가는 길에 바로가기(정션)가 하나도 없어야(바꿔치기 줄이기)
    bind_bad() {
      local src="$1" p="$1" r d
      command -v cygpath >/dev/null 2>&1 && p="$(cygpath -u -- "$src" 2>/dev/null || printf '%s' "$src")"
      [ -e "$p" ] || { echo "볼륨 원본 경로가 없음(먼저 만드세요): $src"; return; }
      r="$(readlink -f -- "$p" 2>/dev/null)"
      case "$r/" in "$APPABS"/*) ;; *) echo "해석된 볼륨이 앱 폴더 밖을 연결: $src"; return ;; esac
      d="$p"
      while [ "$(readlink -f -- "$d" 2>/dev/null)" != "$APPABS" ]; do
        [ -L "$d" ] && { echo "볼륨 원본 길에 바로가기가 있음: $src"; return; }
        case "$d" in /|.|"") echo "볼륨 원본이 앱 폴더 아래가 아님: $src"; return ;; esac
        d="$(dirname -- "$d")"
      done
    }
    binds=()
    while IFS= read -r line; do
      case "$line" in
        BIND$'\t'*) src="${line#BIND$'\t'}"; binds+=("$src"); m="$(bind_bad "$src")"; [ -n "$m" ] && bad="$bad $m;" ;;
        ?*) bad="$bad $line;" ;;
      esac
    done <<< "$rb"
    [ -z "$bad" ] || deny "compose 해석 결과 검사 실패:$bad"
    # 띄우기 바로 직전에 앱 폴더·bind 원본을 한 번 더(그 사이 바꿔치기 막기). 남은 틈: 이 줄과 Docker가 경로를 여는 사이의 아주 짧은 순간
    app_safe
    for src in "${binds[@]}"; do m="$(bind_bad "$src")"; [ -n "$m" ] && deny "띄우기 직전 다시 본 결과: $m"; done
    printf '%s\n' "$resolved" | docker compose -p "ai-$APP" --project-directory "$APPHOST" -f - up -d --wait "$@"
  else
    need_docker
    dk compose -p "ai-$APP" -f "$APPHOST/compose.yaml" down
  fi
  exit $? ;;

ps)
  need_docker
  if [ -n "$1" ]; then app_dir "$1"; dk ps -a --filter "label=ai-workflow.app=$APP" --filter "label=com.docker.compose.project=ai-$APP"
  else dk ps -a --filter "label=ai-workflow.app" --format '{{.Names}}\t{{.Status}}\t{{.Labels}}'; dk ps -a --filter "name=^ai-" --format '{{.Names}}\t{{.Status}}'; fi
  exit $? ;;

clean)
  need_docker
  filt="label=ai-workflow.app"
  if [ -n "$1" ]; then app_dir "$1"; filt="label=ai-workflow.app=$APP"; [ -f "$APPABS/compose.yaml" ] && dk compose -p "ai-$APP" -f "$APPHOST/compose.yaml" down; fi
  if [ $DRY = 1 ]; then dk ps -aq --filter "$filt"; exit 0; fi
  ids="$(docker ps -aq --filter "$filt")"
  [ -n "$ids" ] && docker rm -f $ids >/dev/null && echo "지운 컨테이너: $(printf '%s\n' "$ids" | grep -c .)개 (데이터 볼륨은 그대로)"
  exit 0 ;;

*)
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

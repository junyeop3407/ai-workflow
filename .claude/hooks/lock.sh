#!/usr/bin/env bash
# 자원별 잠금 (사장의 "병렬·직렬 처리 및 동시성 제어 명세", 분석 docs/org-phase2-review.md 1절)
# 전역 잠금 하나가 아니라 **자원 이름마다** 따로 잠근다. 같은 자원은 한 번에 하나, 먼저 온 순서(FIFO).
#   state:<앱>        graph.sh가 그 앱의 state.json을 읽고 고치는 동안
#   env:port:<번호>   테스트·서버가 그 포트를 쓰는 동안 (HANDOFF에 '포트:' 줄이 없으면 env:port:default 하나로 줄 세움)
#
# 사용:
#   lock.sh acquire <이름> [--pid <PID>] [--wait 초] [--lease 초] [--label 설명]  → 세대 번호(토큰) 출력, 0
#   lock.sh release <이름> <토큰>       : 소유자(토큰 일치)만 풀 수 있음
#   lock.sh check <이름> <토큰>         : 아직 내가 소유자인가(세대 번호 확인) — 쓰기 직전에(늦게 깨어난 옛 작업 차단)
#   lock.sh run <이름[,이름…]> [--wait 초] [--lease 초] [--label 설명] -- <명령…>
#                                         : 잡고 → 명령 → 성공·실패·중단 어느 쪽이든 풂. 여러 이름은 정렬 순서로 잡음(교착 방지)
#   lock.sh status [이름 앞부분]          : 잡은 이·대기 수·지연 여부
#
# 동작:
#   - 원자적 획득: 폴더 만들기(mkdir)는 동시에 해도 하나만 성공한다. 번호표도 mkdir로 발급(같은 번호 중복 없음).
#   - FIFO: 살아 있는 번호표 중 가장 작은 번호만 잡을 수 있다.
#   - 죽은 소유자 회수: 잡은 프로세스(--pid, 기본 부모)가 **실제로 끝났을 때만** 회수한다. 시간이 지났다고 회수하지 않는다.
#     lease(기본 600초)가 지나도 살아 있으면 status에 '지연'으로만 표시 → 경영팀·사장 보고 대상.
#   - 세대 번호(fencing token): 잡을 때마다 1씩 오른다. 회수 뒤 옛 작업의 check는 실패한다.
#   - 다시 들어가기: 조상 프로세스가 이미 잡은 이름(LOCK_HELD 환경 변수)은 기다리지 않고 통과(토큰 '-').
#   - 기록: <git 폴더>/locks/log 에 잡음·풂·회수·시간 초과. 잠금 폴더는 커밋되지 않는다.
# 끝 코드: 0 성공 / 1 소유자 아님·확인 실패 / 2 사용법 / 4 기다리다 시간 초과

BASE="${LOCK_DIR:-}"
if [ -z "$BASE" ]; then
  gd="$(git rev-parse --git-common-dir 2>/dev/null)" || { echo "lock.sh: git 저장소 안에서 실행하세요." >&2; exit 2; }
  BASE="$(cd "$gd" && pwd)/locks"
fi
mkdir -p "$BASE" 2>/dev/null

now() { date +%s; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
valid() { printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9:._-]*$'; }
ldir() { printf '%s/%s' "$BASE" "$(printf '%s' "$1" | tr ':' '+')"; }
logl() { printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$2" "$3" >> "$BASE/log" 2>/dev/null; }
held_above() { case " $LOCK_HELD " in *" $1 "*) return 0 ;; esac; return 1; }
rd() { cat "$1" 2>/dev/null; }

# 죽은 소유자·번호표 치우기
reap() {
  local L="$1" name="$2" t p hp
  if [ -d "$L/h" ]; then
    hp="$(rd "$L/h/pid")"
    if [ -n "$hp" ] && ! alive "$hp"; then
      if mv "$L/h" "$L/h.dead.$$" 2>/dev/null; then
        logl reclaim "$name" "세대 $(rd "$L/h.dead.$$/gen") pid $hp 끝남 → 회수 ($(rd "$L/h.dead.$$/label"))"
        rm -rf "$L/h.dead.$$"
      fi
    fi
  fi
  for t in $(ls "$L/q" 2>/dev/null); do
    p="$(rd "$L/q/$t/pid")"
    [ -n "$p" ] && ! alive "$p" && rm -rf "$L/q/$t"
  done
}

acquire() { # 이름 pid wait lease label → 토큰 출력
  local name="$1" pid="$2" wait="$3" lease="$4" label="$5" L n head start gen
  if held_above "$name"; then echo "-"; return 0; fi
  L="$(ldir "$name")"; mkdir -p "$L/q"
  # 번호표 이름 = <순번>-<내 프로세스>-<난수>: 치워진 번호를 다른 사람이 다시 받아도 서로 헷갈리지 않게
  local seq; seq=$(( $(ls "$L/q" 2>/dev/null | cut -d- -f1 | sort -n | tail -n1) + 1 ))
  n="$seq-$$-$RANDOM"
  until mkdir "$L/q/$n" 2>/dev/null; do seq=$((seq+1)); n="$seq-$$-$RANDOM"; done
  echo "$pid" > "$L/q/$n/pid"
  # 기다리다 중단되면(Ctrl+C·종료 신호) 내 번호표를 지워 뒤 사람이 막히지 않게
  trap 'rm -rf "$L/q/$n"; exit 130' INT TERM
  start="$(now)"
  while :; do
    reap "$L" "$name"
    if [ ! -d "$L/q/$n" ]; then   # 내 번호표가 치워짐 = 나를 부른 쪽이 끝남 → 잡지 않고 그만둔다
      logl gone "$name" "pid $pid 번호표 치워짐 — 대기 그만둠 ($label)"
      echo "잠금 '$name' 대기 중 번호표가 치워졌습니다(부른 프로세스 $pid 가 끝남)." >&2; return 4
    fi
    head="$(ls "$L/q" 2>/dev/null | sort -t- -k1,1n -k2,2n | head -n1)"
    if [ "$head" = "$n" ] && mkdir "$L/h" 2>/dev/null; then
      gen=$(( $(rd "$L/gen" || echo 0) + 1 )); echo "$gen" > "$L/gen"
      printf '%s\n' "$pid" > "$L/h/pid"; printf '%s\n' "$gen" > "$L/h/gen"
      printf '%s\n' "$(now)" > "$L/h/since"; printf '%s\n' "$(( $(now) + lease ))" > "$L/h/until"
      printf '%s\n' "$label" > "$L/h/label"
      rm -rf "$L/q/$n"; trap - INT TERM
      logl acquire "$name" "세대 $gen pid $pid ($label)"
      echo "$gen"; return 0
    fi
    if [ $(( $(now) - start )) -ge "$wait" ]; then
      rm -rf "$L/q/$n"
      logl timeout "$name" "pid $pid ${wait}초 기다림 ($label)"
      echo "잠금 '$name'을 ${wait}초 기다렸지만 못 잡았습니다. 잡은 이: $(holder_line "$L")" >&2
      return 4
    fi
    sleep 0.2
  done
}

holder_line() {
  local L="$1"
  [ -d "$L/h" ] || { echo "없음"; return; }
  echo "pid $(rd "$L/h/pid") 세대 $(rd "$L/h/gen") $(( $(now) - $(rd "$L/h/since" || now) ))초째 ($(rd "$L/h/label"))"
}

release() { # 이름 토큰
  local name="$1" tok="$2" L
  [ "$tok" = "-" ] && return 0
  L="$(ldir "$name")"
  if [ -d "$L/h" ] && [ "$(rd "$L/h/gen")" = "$tok" ]; then
    if mv "$L/h" "$L/h.rel.$$" 2>/dev/null; then rm -rf "$L/h.rel.$$"; logl release "$name" "세대 $tok"; return 0; fi
  fi
  echo "잠금 '$name' 세대 $tok 의 소유자가 아니어서 풀지 않았습니다. (지금: $(holder_line "$L"))" >&2
  return 1
}

check() { # 이름 토큰
  local L; [ "$2" = "-" ] && return 0
  L="$(ldir "$1")"
  [ -d "$L/h" ] && [ "$(rd "$L/h/gen")" = "$2" ]
}

opts() { # 공통 옵션 읽기 → PID WAIT LEASE LABEL, 남은 인자는 REST
  PID="$PPID"; WAIT=600; LEASE=600; LABEL=""; REST=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --pid) PID="$2"; shift 2 ;;
      --wait) WAIT="$2"; shift 2 ;;
      --lease) LEASE="$2"; shift 2 ;;
      --label) LABEL="$2"; shift 2 ;;
      --) shift; REST=("$@"); return 0 ;;
      *) REST+=("$1"); shift ;;
    esac
  done
}
num() { printf '%s' "$1" | grep -Eq '^[0-9]+$'; }

cmd="$1"; shift 2>/dev/null
case "$cmd" in
  acquire)
    name="$1"; shift 2>/dev/null; opts "$@"
    valid "$name" && num "$WAIT" && num "$LEASE" && num "$PID" || { echo "사용법: lock.sh acquire <이름> [--pid PID] [--wait 초] [--lease 초] [--label 설명]" >&2; exit 2; }
    acquire "$name" "$PID" "$WAIT" "$LEASE" "$LABEL"; exit $? ;;
  release)
    valid "$1" && [ -n "$2" ] || { echo "사용법: lock.sh release <이름> <토큰>" >&2; exit 2; }
    release "$1" "$2"; exit $? ;;
  check)
    valid "$1" && [ -n "$2" ] || { echo "사용법: lock.sh check <이름> <토큰>" >&2; exit 2; }
    check "$1" "$2"; exit $? ;;
  run)
    names="$1"; shift 2>/dev/null; opts "$@"
    [ ${#REST[@]} -gt 0 ] && num "$WAIT" && num "$LEASE" || { echo "사용법: lock.sh run <이름[,이름…]> [--wait 초] [--lease 초] [--label 설명] -- <명령…>" >&2; exit 2; }
    sorted="$(printf '%s\n' "$names" | tr ',' '\n' | grep . | LC_ALL=C sort -u)"
    for n in $sorted; do valid "$n" || { echo "잘못된 잠금 이름: $n" >&2; exit 2; }; done
    got=()
    free_all() { local i; for (( i=${#got[@]}-1; i>=0; i-- )); do release "${got[$i]%%=*}" "${got[$i]#*=}" >/dev/null 2>&1; done; got=(); }
    trap 'free_all' EXIT
    trap 'free_all; exit 130' INT TERM
    for n in $sorted; do
      t="$(acquire "$n" "$$" "$WAIT" "$LEASE" "${LABEL:-${REST[*]}}")" || exit 4
      got+=("$n=$t")
      held_above "$n" || LOCK_HELD="${LOCK_HELD:+$LOCK_HELD }$n"
    done
    export LOCK_HELD
    "${REST[@]}"; rc=$?
    free_all
    exit $rc ;;
  status)
    pre="${1:-}"; any=0
    for L in "$BASE"/*/; do
      [ -d "$L" ] || continue
      name="$(basename "$L" | tr '+' ':')"
      case "$name" in "$pre"*) ;; *) continue ;; esac
      q=$(ls "$L/q" 2>/dev/null | grep -c .)
      if [ -d "$L/h" ]; then
        flag=""; [ "$(now)" -gt "$(rd "$L/h/until" || echo 0)" ] && flag=" — 지연(lease 넘김)"
        alive "$(rd "$L/h/pid")" || flag=" — 소유자 끝남(다음에 회수)"
        echo "$name: 잡힘 $(holder_line "$L"), 대기 $q$flag"; any=1
      elif [ "$q" -gt 0 ]; then
        echo "$name: 비어 있음, 대기 $q"; any=1
      fi
    done
    [ $any -eq 1 ] || echo "잡힌 잠금 없음${pre:+ ($pre)}"
    exit 0 ;;
  *)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

#!/usr/bin/env bash
# 잠금 도구(lock.sh) 시험 — 사장의 동시성 명세 17절 중 이 작업장에 맞는 시나리오.
# 임시 git 저장소에서만 돈다(실제 저장소의 잠금은 건드리지 않음). 기대와 다르면 exit 1.
# 사용: bash .claude/hooks/test-lock.sh

src="$(git rev-parse --show-toplevel)" || exit 1
K="$src/.claude/hooks/lock.sh"
tmp="$(mktemp -d)"; pids=()
cleanup() { local p; for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$tmp"; }
trap cleanup EXIT
cd "$tmp" && git init -q . || exit 1
L() { bash "$K" "$@"; }
fails=0; rows=""
row() { local ok="✅"; [ "$2" = "$3" ] || { ok="❌"; fails=$((fails+1)); }; rows="$rows
| $1 | $2 | $3 | $ok |"; }
bg_sleep() { sleep "$1" >/dev/null 2>&1 & h=$!; pids+=("$h"); }   # 살아 있는 "소유자" 프로세스 → $h

# 1. 기본: 잡기·풀기·남의 토큰
t="$(L acquire x --pid $$)"
row "잡기 → 세대 번호 1" 1 "$t"
row "틀린 토큰으로 풀기 → 거부" 1 "$(L release x 99 2>/dev/null; echo $?)"
row "맞는 토큰으로 풀기" 0 "$(L release x "$t"; echo $?)"
row "같은 토큰으로 두 번 풀기 → 거부" 1 "$(L release x "$t" 2>/dev/null; echo $?)"

# 2. 동시에 하나만 (명세 테스트 6·11): 6개를 동시에 — 임계구역 안에 둘이 있으면 표시
echo 0 > n.txt; : > overlap.txt
crit='mkdir in.d 2>/dev/null || echo 겹침 >> overlap.txt; v=$(cat n.txt); sleep 0.2; echo $((v+1)) > n.txt; rmdir in.d'
w=(); for i in 1 2 3 4 5 6; do L run shared -- bash -c "$crit" & w+=($!); done; wait "${w[@]}"
row "동시에 6개 → 결과 6(덮어쓰기 없음)" 6 "$(cat n.txt)"
row "동시에 6개 → 임계구역 겹침 0" 0 "$(grep -c 겹침 overlap.txt)"

# 3. 먼저 온 순서 (명세 테스트 1·2)
bg_sleep 60; t="$(L acquire q --pid "$h")"
: > order.txt
w=(); for i in 1 2 3; do L run q --label "대기 $i" -- bash -c "echo $i >> order.txt" & w+=($!); sleep 0.6; done
L release q "$t"; wait "${w[@]}"
row "대기 1·2·3 → 접수 순서대로 실행" "1 2 3" "$(paste -sd' ' order.txt)"

# 4. 독립 자원은 안 기다림 (명세 테스트 3·10)
bg_sleep 60; t="$(L acquire a --pid "$h")"
s=$(date +%s); L run b --wait 3 -- true; r=$?; e=$(( $(date +%s) - s ))
row "a를 잡은 동안 b → 바로 실행" "0 빠름" "$r $([ $e -le 2 ] && echo 빠름 || echo 느림${e}초)"
L release a "$t"

# 5. 실패해도 풀림 (명세 테스트 4)
L run f -- bash -c 'exit 7'; r=$?
row "명령 실패 → 끝 코드 그대로(7)" 7 "$r"
row "실패 뒤 잠금 풀림 → 다음이 바로 잡음" 0 "$(L run f --wait 2 -- true; echo $?)"

# 6. 죽은 소유자 회수 + 옛 작업 차단 (명세 테스트 7·8)
bg_sleep 60; old="$(L acquire d --pid "$h")"
kill "$h" 2>/dev/null; wait "$h" 2>/dev/null
new="$(L acquire d --pid $$ --wait 5)"; r=$?
row "소유자 프로세스가 끝남 → 회수하고 잡음" "0 큼" "$r $([ "${new:-0}" -gt "${old:-0}" ] && echo 큼 || echo 작음)"
row "회수 뒤 옛 토큰 check → 실패(늦게 깨어난 작업 차단)" 1 "$(L check d "$old"; echo $?)"
row "새 토큰 check → 통과" 0 "$(L check d "$new"; echo $?)"
L release d "$new"

# 7. 살아 있는데 오래 걸림 → 회수하지 않고 '지연'만 (명세 11-3: 시간만 보고 회수 금지)
bg_sleep 60; t="$(L acquire s --pid "$h" --lease 1)"; sleep 2
row "lease 넘겼지만 살아 있음 → 다른 작업은 시간 초과(4)" 4 "$(L acquire s --pid $$ --wait 2 2>/dev/null; echo $?)"
row "status에 '지연' 표시" 1 "$(L status s | grep -c 지연)"
row "시간 초과한 대기자의 번호표는 지워짐" "대기 0" "$(L status s | grep -o '대기 [0-9]*')"
L release s "$t"

# 8. 대기자가 죽어도 줄이 멈추지 않음 (명세 11-2)
bg_sleep 60; t="$(L acquire w --pid "$h")"
bg_sleep 60; caller="$h"   # 기다리는 쪽을 부른 프로세스(graph.sh 같은) — 이게 죽는 경우
bash "$K" acquire w --pid "$caller" --wait 8 >/dev/null 2>&1 & orphan=$!; sleep 0.6
kill "$caller" 2>/dev/null; wait "$caller" 2>/dev/null
( L run w --wait 10 -- true; echo $? > w.rc ) & w1=$!; sleep 0.6
L release w "$t"; wait "$w1"
row "앞 대기자를 부른 쪽이 죽음 → 뒤 대기자가 잡음" 0 "$(cat w.rc)"
bg_sleep 60; t="$(L acquire w2 --pid "$h")"
bash "$K" acquire w2 --pid $$ --wait 30 >/dev/null 2>&1 & direct=$!
sleep 0.6; kill "$direct" 2>/dev/null; wait "$direct" 2>/dev/null
row "기다리던 lock.sh가 종료 신호를 받음 → 번호표 지움" "대기 0" "$(L status w2 | grep -o '대기 [0-9]*')"
L release w2 "$t"; wait "$orphan" 2>/dev/null

# 9. 다시 들어가기: 잡은 상태에서 자식이 같은 이름 → 기다리지 않음
row "run 안에서 같은 이름 run → 교착 없음" 0 "$(L run r --wait 3 -- bash "$K" run r --wait 3 -- true; echo $?)"
# 10. 여러 이름은 정렬 순서로(교착 방지): 반대 순서로 동시에
L run p2,p1 --wait 10 -- sleep 0.3 & a1=$!; L run p1,p2 --wait 10 -- sleep 0.3 & a2=$!; wait "$a1" "$a2"
row "p1,p2 / p2,p1 동시에 → 둘 다 끝남(교착 없음)" "잡힌 잠금 없음 (p)" "$(L status p)"
# 11. 잘못된 이름
row "잘못된 이름(대문자·공백) → 사용법 오류(2)" 2 "$(L acquire 'Bad Name' 2>/dev/null; echo $?)"
# 12. 기록
row "기록에 잡음·풂·회수·시간 초과가 남음" "4" "$(cut -f2 "$(git rev-parse --git-dir)/locks/log" | sort -u | grep -c -E '^(acquire|release|reclaim|timeout)$')"

echo "## 잠금 도구 시험"
echo "| 경우 | 기대 | 실제 | |"
echo "|---|---|---|---|$rows"
echo
if [ $fails -eq 0 ]; then echo "전부 기대대로입니다."; else echo "기대와 다른 경우: $fails개"; exit 1; fi

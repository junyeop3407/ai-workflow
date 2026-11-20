#!/usr/bin/env bash
# api.md 의 예시 요청을 실제 로컬 서버에 보내 예시 응답대로 나오는지 확인한다 (graph.md bb 노드).
# 사용: bash .claude/skills/build-app/api-check.sh docs/api.md http://localhost:8080
# api.md 예시 형식 (graph.md "파일 형식"):
#   ### 요청: POST /api/items {"name": "우유", "price": 1000}
#   ### 응답: 201 {"id": "<아무거나>", "name": "우유", "price": 1000}
# 비교: 상태 코드가 같고, 예시 응답의 "키": 값(문자열·숫자·true/false/null)이 실제 응답에 모두 있으면 통과.
#       공백은 무시하고, "<아무거나>" 는 키가 있는지만 본다. 중첩된 객체 안의 키도 글자로 찾는다.
# localhost·127.0.0.1 주소만 받는다. jq 없이 동작한다. 결과: 0 모두 통과 / 1 하나라도 다름·예시 없음.

md="$1"; base="${2%/}"
[ -f "$md" ] || { echo "api-check: $md 가 없습니다." >&2; exit 1; }
case "$base" in http://localhost:*|http://127.0.0.1:*) ;; *) echo "api-check: localhost 주소만 됩니다 ($base)" >&2; exit 1 ;; esac
command -v curl >/dev/null 2>&1 || { echo "api-check: curl 이 없습니다." >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
n=0; bad=0; req=""
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | tr -d '\r')"
  case "$line" in
    "### 요청: "*) req="${line#\#\#\# 요청: }" ;;
    "### 응답: "*)
      [ -z "$req" ] && { echo "✗ 요청 줄 없이 응답 줄이 있음: $line"; bad=$((bad+1)); continue; }
      res="${line#\#\#\# 응답: }"; n=$((n+1))
      method="${req%% *}"; rest="${req#* }"; path="${rest%% *}"; body=""
      [ "$rest" != "$path" ] && body="${rest#* }"
      code="${res%% *}"; want=""; [ "$res" != "$code" ] && want="${res#* }"
      if [ -n "$body" ]; then
        got="$(curl -s -o "$tmp/body" -w '%{http_code}' -X "$method" -H 'Content-Type: application/json' --data-binary "$body" "$base$path")"
      else
        got="$(curl -s -o "$tmp/body" -w '%{http_code}' -X "$method" "$base$path")"
      fi
      flat="$(tr -d ' \t\r\n' < "$tmp/body" 2>/dev/null)"
      miss=""
      if [ "$got" != "$code" ]; then
        miss="상태 코드 기대 $code, 받음 ${got:-없음}"
      elif [ -n "$want" ]; then
        # 예시 응답의 "키":값 쌍을 하나씩 꺼내 실제 응답(공백 제거)에서 찾는다
        pairs="$(printf '%s' "$want" | tr -d ' \t' | grep -oE '"[^"]+":("[^"]*"|-?[0-9.]+|true|false|null)')"
        while IFS= read -r p; do
          [ -z "$p" ] && continue
          case "$p" in
            *':"<아무거나>"') k="${p%%:*}"; printf '%s' "$flat" | grep -qF "$k:" || miss="$miss $k 없음" ;;
            *) printf '%s' "$flat" | grep -qF "$p" || miss="$miss $p 다름" ;;
          esac
        done <<< "$pairs"
      fi
      if [ -z "$miss" ]; then echo "✓ $method $path → $code"
      else echo "✗ $method $path —$miss"; bad=$((bad+1)); fi
      req="" ;;
  esac
done < "$md"

[ $n -eq 0 ] && { echo "✗ $md 에 예시(### 요청: / ### 응답:)가 없습니다."; exit 1; }
echo "api 예시 $n개 중 $((n-bad))개 일치"
[ $bad -eq 0 ]

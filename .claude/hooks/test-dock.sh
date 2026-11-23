#!/usr/bin/env bash
# dock.sh 시험 — Docker가 없어도 돈다(--dry-run 미리보기 + 가짜 docker). 임시 git 저장소에서만. 기대와 다르면 exit 1.
# 사용: bash .claude/hooks/test-dock.sh

src="$(git rev-parse --show-toplevel)" || exit 1
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" && git init -q . || exit 1
mkdir -p .claude/hooks .claude/skills/build-app/templates/docker apps/shop fakebin
cp "$src/.claude/hooks/dock.sh" "$src/.claude/hooks/lock.sh" .claude/hooks/
IM=.claude/skills/build-app/templates/docker/images.txt
D1="sha256:$(printf 'a%.0s' $(seq 64))"; D2="sha256:$(printf 'b%.0s' $(seq 64))"
cat > "$IM" <<EOF
# 시험용
postgres   postgres:17              $D1  -          DB
node       node:22-bookworm-slim    $D2  node       화면
temurin    eclipse-temurin:21-jdk   -    1000:1000  아직 고정 안 됨
rooty      busybox:1.36             $D2  root       root로 도는 이미지(거부돼야)
EOF
K() { bash .claude/hooks/dock.sh "$@"; }
fails=0; rows=""
row() { local ok="✅"; [ "$2" = "$3" ] || { ok="❌"; fails=$((fails+1)); }; rows="$rows
| $1 | $2 | $3 | $ok |"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
has() { "${@:2}" 2>&1 | grep -qF -- "$1" && echo 있음 || echo 없음; }

# ---- run: 정책 ----
out="$(K --dry-run run apps/shop node -- npm test 2>&1)"
for f in "--rm" "--cap-drop ALL" "--security-opt no-new-privileges" "--pids-limit 512" "--read-only" "--network none" "--user node" "--memory 2g" "-w /workspace" "node:22-bookworm-slim@$D2" "--label ai-workflow.app=shop"; do
  row "run 미리보기에 '$f'" 있음 "$(printf '%s' "$out" | grep -qF -- "$f" && echo 있음 || echo 없음)"
done
row "run: 앱 폴더만 /workspace 로 연결" 있음 "$(printf '%s' "$out" | grep -qE -- "-v [^ ]*apps/shop:/workspace" && echo 있음 || echo 없음)"
row "run: 고정 안 된 이미지(temurin) → 거부(2)" 2 "$(rc K --dry-run run apps/shop temurin -- java -version)"
row "run: 허용 목록에 없는 별명 → 거부(2)" 2 "$(rc K --dry-run run apps/shop alpine -- sh)"
row "run: root로 도는 이미지 → 거부(2)" 2 "$(rc K --dry-run run apps/shop rooty -- sh)"
row "run: compose 서비스용 이미지(postgres)를 run → 거부(2)" 2 "$(rc K --dry-run run apps/shop postgres -- psql)"
row "run: docker 옵션 직접 넘기기(--privileged) → 거부(2)" 2 "$(rc K --dry-run run apps/shop node --privileged -- sh)"
row "run: -v 로 다른 폴더 연결 시도 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node -v /:/host -- sh)"
row "run: 메모리 99g → 거부(2)" 2 "$(rc K --dry-run run apps/shop node --mem 99g -- sh)"
row "run: 시간 5시간 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node --time 18000 -- sh)"
row "run: 앱 이름에 ../ → 거부(2)" 2 "$(rc K --dry-run run apps/../etc node -- sh)"
row "run: 없는 앱 → 거부(2)" 2 "$(rc K --dry-run run apps/nope node -- sh)"
row "run: 명령 없음 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node)"
row "run: --port 인데 네트워크 없음 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node --port 8081:3000 -- npm start)"
out="$(K --dry-run run apps/shop node --net out --port 8081:3000 -- npm start 2>&1)"
row "run: --port 는 127.0.0.1 에만" 있음 "$(printf '%s' "$out" | grep -qF -- "-p 127.0.0.1:8081:3000" && echo 있음 || echo 없음)"
row "run: --port 쓰면 그 포트 잠금(env:port:8081)" 있음 "$(printf '%s' "$out" | grep -qF -- "env:port:8081" && echo 있음 || echo 없음)"
row "run: --net out → bridge" 있음 "$(printf '%s' "$out" | grep -qF -- "--network bridge" && echo 있음 || echo 없음)"
row "run: --port 주소 넣기(0.0.0.0:80:80) → 거부(2)" 2 "$(rc K --dry-run run apps/shop node --net out --port 0.0.0.0:80:80 -- sh)"
row "run: --env 인데 .env 없음 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node --env -- sh)"
echo 'A=1' > apps/shop/.env
row "run: --env → --env-file 로 실행 때만" 있음 "$(K --dry-run run apps/shop node --env -- sh 2>&1 | grep -qF -- "--env-file" && echo 있음 || echo 없음)"
rm apps/shop/.env

# ---- up: compose 검사 ----
good() { cat > apps/shop/compose.yaml <<EOF
services:
  db:
    image: postgres:17@$D1
    environment:
      POSTGRES_PASSWORD: \${DB_PASSWORD}
    ports:
      - "127.0.0.1:55432:5432"
    volumes:
      - dbdata:/var/lib/postgresql/data
      - ./seed:/docker-entrypoint-initdb.d
volumes:
  dbdata:
EOF
}
good; row "up: 규칙에 맞는 compose → 통과(미리보기)" 0 "$(rc K --dry-run up apps/shop)"
row "up: 프로젝트 이름 ai-<앱>·--wait" 있음 "$(K --dry-run up apps/shop 2>&1 | grep -qF -- "-p ai-shop" && K --dry-run up apps/shop 2>&1 | grep -qF -- "--wait" && echo 있음 || echo 없음)"
bad() { good; sed -i.bak "$1" apps/shop/compose.yaml; rm -f apps/shop/compose.yaml.bak; rc K --dry-run up apps/shop; }
row "up: privileged → 거부(2)" 2 "$(bad 's/^    image:/    privileged: true\n    image:/')"
row "up: Docker 소켓 연결 → 거부(2)" 2 "$(bad 's#- dbdata:/var/lib/postgresql/data#- /var/run/docker.sock:/var/run/docker.sock#')"
row "up: 포트를 모든 주소에(0.0.0.0) → 거부(2)" 2 "$(bad 's/127.0.0.1:55432:5432/55432:5432/')"
row "up: 허용 목록에 없는 이미지 → 거부(2)" 2 "$(bad 's#postgres:17@.*#postgres:latest#')"
row "up: 다이제스트만 다른 이미지 → 거부(2)" 2 "$(bad "s#$D1#$D2#")"
row "up: 비밀번호를 파일에 직접 → 거부(2)" 2 "$(bad 's/\${DB_PASSWORD}/hunter2/')"
row "up: 앱 폴더 밖 볼륨(../) → 거부(2)" 2 "$(bad 's#./seed:#../other:#')"
row "up: 내 컴퓨터 절대 경로 볼륨 → 거부(2)" 2 "$(bad 's#./seed:#/etc:#')"
row "up: build: (직접 이미지 만들기) → 거부(2)" 2 "$(bad 's/^    image:/    build: .\n    image:/')"
row "up: network_mode: host → 거부(2)" 2 "$(bad 's/^    image:/    network_mode: host\n    image:/')"
row "up: YAML 앵커(&x) → 거부(2)" 2 "$(bad 's/^  db:/  db: \&base/')"
row "up: seccomp 끄기 → 거부(2)" 2 "$(bad 's/^    image:/    security_opt: [seccomp:unconfined]\n    image:/')"
rm apps/shop/compose.yaml
row "up: compose.yaml 없음 → 거부(2)" 2 "$(rc K --dry-run up apps/shop)"

# ---- check·pin: Docker 없음 / 가짜 docker ----
nodock="$tmp/fakebin:$(dirname "$(command -v git)"):$(dirname "$(command -v awk)"):/usr/bin:/bin"   # git·awk는 두고 docker만 없는 PATH
row "check: Docker 없음 → 3(설치 안내)" 3 "$(PATH="$nodock" rc K check)"
cat > fakebin/docker <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "info") exit 0 ;;
  *"imagetools inspect"*eclipse-temurin*)
    printf 'Name: x\nMediaType: application/vnd.oci.image.index.v1+json\nDigest:    sha256:%s\n\nManifests:\n  Platform:  linux/amd64\n  Platform:  linux/arm64\n' "$(printf 'c%.0s' $(seq 64))" ;;
  *"imagetools inspect"*)
    printf 'Name: x\nDigest:    sha256:%s\n\nManifests:\n  Platform:  linux/amd64\n' "$(printf 'd%.0s' $(seq 64))" ;;
  *) exit 0 ;;
esac
EOF
chmod +x fakebin/docker
row "pin: amd64·arm64 둘 다 있음 → 다이제스트 고정" 고정 "$(PATH="$tmp/fakebin:$PATH" K pin temurin >/dev/null 2>&1; grep -q "^temurin .*sha256:cccc" "$IM" && echo 고정 || grep '^temurin' "$IM")"
row "pin 뒤 temurin run → 통과(미리보기)" 0 "$(rc K --dry-run run apps/shop temurin -- ./gradlew test)"
row "pin: arm64 판이 없음(Mac에서 못 씀) → 거부(2)" 2 "$(PATH="$tmp/fakebin:$PATH" rc K pin node)"
printf 'bad  alpine:latest  -  nobody  x\n' >> "$IM"
row "pin: latest 태그 → 거부(2)" 2 "$(PATH="$tmp/fakebin:$PATH" rc K pin bad)"

echo "## dock.sh 시험"
echo "| 경우 | 기대 | 실제 | |"
echo "|---|---|---|---|$rows"
echo
if [ $fails -eq 0 ]; then echo "전부 기대대로입니다."; else echo "기대와 다른 경우: $fails개"; exit 1; fi

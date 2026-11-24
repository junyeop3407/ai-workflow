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
# 원본 파일: 허용된 설정 이름만·흐름 문법·따옴표 키·긴 볼륨 문법 금지
row "up: 서비스에 env_file(허용 목록 밖) → 거부(2)" 2 "$(bad 's/^    image:/    env_file: ..\/..\/secret\n    image:/')"
row "up: 긴 볼륨 문법(type:/source:) → 거부(2)" 2 "$(bad 's#      - ./seed:/docker-entrypoint-initdb.d#      - type: bind\n        source: /etc\n        target: /x#')"
row "up: 흐름 문법(healthcheck test: [...]) → 거부(2)" 2 "$(bad 's/^    image:/    healthcheck:\n      test: [\"CMD\", \"true\"]\n    image:/')"
row "up: 따옴표 붙은 키(\"privileged\": true) → 거부(2)" 2 "$(bad 's/^    image:/    \"privileged\": true\n    image:/')"
row "up: 맨 위 x-공통 설정 → 거부(2)" 2 "$(bad 's/^services:/x-common:\n  a: 1\nservices:/')"
row "up: 이름 붙은 볼륨에 driver_opts(내 폴더 연결) → 거부(2)" 2 "$(bad 's/^  dbdata:/  dbdata:\n    driver_opts:\n      device: \/etc/')"
row "up: 서비스 이름 자리에 옵션(--build) → 거부(2)" 2 "$(good; rc K --dry-run up apps/shop --build)"
row "up 미리보기: 해석(config) → 그 결과를 표준 입력으로(-f -)" 있음 "$(good; K --dry-run up apps/shop 2>&1 | grep -qF -- "config" && K --dry-run up apps/shop 2>&1 | grep -qF -- "-f - up" && echo 있음 || echo 없음)"
rm apps/shop/compose.yaml
row "up: compose.yaml 없음 → 거부(2)" 2 "$(rc K --dry-run up apps/shop)"

# ---- up: Docker가 해석한 결과 검사 (가짜 docker가 compose config 출력을 흉내) ----
mkdir -p apps/shop/seed outside
win() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }
SEED="$(win "$tmp/apps/shop/seed")"
cat > fakebin/docker <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "info") exit 0 ;;
  *compose*" config"*) cat "$FAKE_CFG" ;;
  *compose*" up "*) cat > "$FAKE_UPIN" ;;
  *) exit 0 ;;
esac
EOF
chmod +x fakebin/docker
export FAKE_CFG="$tmp/cfg.yaml" FAKE_UPIN="$tmp/upin.yaml"
rcfg() { cat > "$FAKE_CFG" <<EOF
name: ai-shop
services:
  db:
    environment:
      POSTGRES_PASSWORD: hunter2
    image: postgres:17@$D1
    networks:
      default: null
    ports:
      - mode: ingress
        host_ip: 127.0.0.1
        target: 5432
        published: "55432"
        protocol: tcp
    security_opt:
      - no-new-privileges:true
    volumes:
      - type: volume
        source: dbdata
        target: /var/lib/postgresql/data
        volume: {}
      - type: bind
        source: $SEED
        target: /docker-entrypoint-initdb.d
        bind:
          create_host_path: true
networks:
  default:
    name: ai-shop_default
volumes:
  dbdata:
    name: ai-shop_dbdata
EOF
}
FD() { PATH="$tmp/fakebin:$PATH" K "$@"; }
rbad() { good; rcfg; sed -i.bak "$1" "$FAKE_CFG"; rm -f "$FAKE_CFG.bak"; FD up apps/shop >/dev/null 2>&1; echo $?; }
good; rcfg; rm -f "$FAKE_UPIN"
row "해석: 규칙에 맞는 결과 → 띄움(0)" 0 "$(FD up apps/shop >/dev/null 2>&1; echo $?)"
row "해석: 검사한 결과 그대로를 up 에 넘김" 같음 "$(cmp -s "$FAKE_CFG" "$FAKE_UPIN" && echo 같음 || echo 다름)"
row "해석: bind 원본이 앱 폴더 밖(원본은 통과) → 거부(2)" 2 "$(rbad "s#source: .*seed#source: $(win "$tmp/outside" | sed 's/\\/\\\\/g')#")"
row "해석: 포트가 0.0.0.0 → 거부(2)" 2 "$(rbad 's/host_ip: 127.0.0.1/host_ip: 0.0.0.0/')"
row "해석: 포트에 host_ip 없음(모든 주소) → 거부(2)" 2 "$(rbad '/host_ip: 127.0.0.1/d')"
row "해석: privileged → 거부(2)" 2 "$(rbad 's/^    image:/    privileged: true\n    image:/')"
row "해석: cap_add → 거부(2)" 2 "$(rbad 's/^    image:/    cap_add:\n      - SYS_ADMIN\n    image:/')"
row "해석: 이미지가 허용 목록과 다름 → 거부(2)" 2 "$(rbad "s#postgres:17@$D1#postgres:17#")"
row "해석: user root → 거부(2)" 2 "$(rbad 's/^    image:/    user: \"0:0\"\n    image:/')"
row "해석: security_opt seccomp 끄기 → 거부(2)" 2 "$(rbad 's/no-new-privileges:true/seccomp=unconfined/')"
row "해석: 볼륨 종류 image → 거부(2)" 2 "$(rbad 's/type: volume/type: image/')"
row "해석: 이름 붙은 볼륨에 driver_opts → 거부(2)" 2 "$(rbad 's/    name: ai-shop_dbdata/    driver_opts:\n      device: \/etc\n    name: ai-shop_dbdata/')"
row "해석: 모르는 흐름 문법 → 거부(2)" 2 "$(rbad 's/default: null/default: {aliases: [x]}/')"
row "해석: 맨 위 secrets → 거부(2)" 2 "$(rbad 's/^networks:/secrets:\n  s:\n    file: \/etc\/passwd\nnetworks:/')"
row "해석 실패 메시지에 비밀값이 안 나옴" 없음 "$(good; rcfg; sed -i.bak 's/^    image:/    privileged: true\n    image:/' "$FAKE_CFG"; FD up apps/shop 2>&1 | grep -qF hunter2 && echo 있음 || echo 없음)"
rm -f apps/shop/compose.yaml

# ---- 바로가기·정션 ----
mkln() { if command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -w "$1")" "$(cygpath -w "$2")" >/dev/null 2>&1; else ln -s "$2" "$1"; fi; }
mkln apps/shop/in-link "$tmp/apps/shop/seed"
row "앱 안을 가리키는 바로가기(node_modules/.bin 같은) → 통과" 0 "$(rc K --dry-run run apps/shop node -- sh)"
mkln apps/shop/out-link "$tmp/outside"
row "앱 밖을 가리키는 바로가기·정션 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node -- sh)"
rm -f apps/shop/out-link apps/shop/in-link 2>/dev/null
[ -e apps/shop/out-link ] && MSYS2_ARG_CONV_EXCL='*' cmd /c rmdir "$(cygpath -w "$tmp/apps/shop/out-link")" >/dev/null 2>&1
row "바로가기를 치운 뒤 → 통과" 0 "$(rc K --dry-run run apps/shop node -- sh)"
mv apps realapps && mkln apps "$tmp/realapps"
row "apps/ 폴더 자체가 바로가기 → 거부(2)" 2 "$(rc K --dry-run run apps/shop node -- sh)"
rm -rf apps 2>/dev/null; [ -e apps ] || mv realapps apps
rm -f fakebin/docker; unset FAKE_CFG FAKE_UPIN

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

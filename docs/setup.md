# 처음 쓰는 컴퓨터 준비 (한 번만)

루트 `HANDOFF.md`에서 옮김(매 세션 읽을 필요가 없어서). 새 컴퓨터에서만 읽는다.
1. git 설치 (Windows는 Git Bash가 함께 깔림. 훅이 bash로 돈다). **Mac**: 터미널에서 `xcode-select --install`(git·bash 포함) → Homebrew 설치(https://brew.sh 의 한 줄)
2. GitHub CLI: `winget install GitHub.cli` (Mac `brew install gh`) → `gh auth login --web` → `gh auth setup-git`
3. 저장소 받기: `git clone <이 저장소 주소>`
4. 이 폴더를 Claude Code로 처음 열면 superpowers·modern-web-guidance·context7·chrome-devtools-mcp·ecc 플러그인 설치를 묻는다 → 모두 "예" (ecc는 개인 개발자 affaan-m의 공개 플러그인. 이 저장소 설정이 공식 저장소 `affaan-m/ECC`에서만 받게 되어 있다) (chrome-devtools는 Chrome 브라우저가 깔려 있어야 함)
   - context7은 처음 한 번 로그인해야 쓸 수 있다: `/mcp` → context7 → Authenticate → 열리는 브라우저에서 로그인. `claude mcp list`에 context7이 `Needs authentication`으로 나오면 아직 안 한 것
5. git 이름·이메일이 없으면: `git config user.name "이름"`, `git config user.email "메일"`
6. 팀 기본 기술 도구 (첫 앱을 만들 때 Claude가 필요한 것만 설치를 안내한다):
   - Java (백엔드팀): `winget install --id EclipseAdoptium.Temurin.21.JDK -e` (Mac `brew install --cask temurin@21`)
   - Node.js (프론트엔드팀·디자인팀·QA팀의 React, Vite, Tailwind, Playwright, Vitest): `winget install --id OpenJS.NodeJS.LTS -e` (Mac `brew install node`)
   - Playwright 브라우저 (QA팀, 앱 폴더에서 한 번): `npx playwright install chromium webkit` (webkit은 Safari 엔진, 호환성 테스트용)
   - 파이썬으로 테스트하는 앱일 때만: `py -m pip install pytest playwright` → `py -m playwright install chromium` (Mac은 `python3`)
7. **Mac에서 처음 한 번 시험**: `bash .claude/hooks/test-hooks.sh --settings` · `bash .claude/hooks/test-lock.sh` · `bash .claude/hooks/test-graph.sh` — 모두 "전부 기대대로"면 Mac 준비 끝(시험 스크립트는 Mac sed에 맞춰 고쳤지만 Mac에서 실제로 돌려 본 적은 아직 없음)

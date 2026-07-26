#!/usr/bin/env bash
# KLECT — full verification sweep.
#
#   bash scripts/verify.sh          # everything
#   bash scripts/verify.sh mobile   # just Flutter
#   bash scripts/verify.sh web      # just Next.js
#   bash scripts/verify.sh tokens   # just the design-token contract
#
# Exits non-zero if anything fails. This is the gate referenced by docs/CHECKLIST.md §I.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
TARGET="${1:-all}"
FAILED=()
PASSED=()

export PATH="/c/src/flutter/bin:$PATH"

bold() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
run() {
  local name="$1"; shift
  printf '  → %s ... ' "$name"
  if out=$("$@" 2>&1); then
    printf '\033[32mpass\033[0m\n'; PASSED+=("$name")
  else
    printf '\033[31mFAIL\033[0m\n'; FAILED+=("$name")
    printf '%s\n' "$out" | tail -25 | sed 's/^/      /'
  fi
}

# ─────────────────────────────────────────────── tokens
if [[ "$TARGET" == all || "$TARGET" == tokens ]]; then
  bold "Design tokens"
  run "tokens.json is valid JSON" node -e "JSON.parse(require('fs').readFileSync('packages/tokens/tokens.json','utf8'))"
  run "generator runs clean"      node packages/tokens/build.mjs

  printf '  → generated files match tokens.json ... '
  if git rev-parse --git-dir >/dev/null 2>&1 && \
     ! git diff --quiet -- mobile/lib/design/tokens.g.dart web/src/styles/tokens.g.css web/src/design/tokens.g.ts 2>/dev/null; then
    printf '\033[31mFAIL\033[0m (regenerate and commit)\n'; FAILED+=("tokens in sync")
  else
    printf '\033[32mpass\033[0m\n'; PASSED+=("tokens in sync")
  fi

  # A raw hex in application code defeats the whole token system.
  printf '  → no hardcoded hex in app code ... '
  hits=$(grep -rEn "0xFF[0-9A-Fa-f]{6}" mobile/lib --include="*.dart" 2>/dev/null | grep -v "tokens.g.dart" | head -10)
  hits+=$(grep -rEn "#[0-9A-Fa-f]{6}\b" web/src --include="*.tsx" --include="*.ts" --include="*.css" 2>/dev/null \
            | grep -v "tokens.g" | head -10)
  if [[ -n "$hits" ]]; then
    printf '\033[33mwarn\033[0m\n'; printf '%s\n' "$hits" | sed 's/^/      /'
  else
    printf '\033[32mpass\033[0m\n'; PASSED+=("no raw hex")
  fi
fi

# ─────────────────────────────────────────────── mobile
if [[ "$TARGET" == all || "$TARGET" == mobile ]]; then
  bold "Flutter (mobile)"
  if ! command -v flutter >/dev/null 2>&1; then
    echo "  flutter not on PATH — expected at C:/src/flutter/bin"; FAILED+=("flutter missing")
  else
    cd "$ROOT/mobile" || exit 1
    run "pub get"            flutter pub get
    run "analyze"            flutter analyze
    run "test"               flutter test
    run "build web"          flutter build web --release
    cd "$ROOT" || exit 1
    echo "  note: apk/ipa need a JDK+Android SDK / Xcode — not installable here."
  fi
fi

# ─────────────────────────────────────────────── web
if [[ "$TARGET" == all || "$TARGET" == web ]]; then
  bold "Next.js (web + admin)"
  cd "$ROOT/web" || exit 1
  [[ -d node_modules ]] || run "npm install" npm install
  run "typecheck"  npx tsc --noEmit
  run "lint"       npx next lint
  run "build"      npx next build
  cd "$ROOT" || exit 1
fi

# ─────────────────────────────────────────────── summary
bold "Summary"
printf '  passed: %d\n' "${#PASSED[@]}"
if ((${#FAILED[@]})); then
  printf '  \033[31mfailed: %d\033[0m\n' "${#FAILED[@]}"
  for f in "${FAILED[@]}"; do printf '    ✗ %s\n' "$f"; done
  echo
  echo "  Fix these before updating docs/PROJECT_STATE.md to 'done'."
  exit 1
fi
printf '  \033[32mall green\033[0m\n'

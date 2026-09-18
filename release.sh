#!/usr/bin/env bash
#
# opencode-dir release script
#
# Usage: ./release.sh [patch|minor|major] ["release message"]
#   patch: 1.2.6 -> 1.2.7 (default)
#   minor: 1.2.6 -> 1.3.0
#   major: 1.2.6 -> 2.0.0
#   message: optional commit/tag note, e.g. "fix: ship lib.protocol.ts"
#
# Gates on typecheck + tests, then bumps version, commits, tags, pushes.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

BUMP="${1:-patch}"
MSG="${2:-}"

# Pre-release gates — run BEFORE any version bump (node-only)
log_info "Running typecheck..."
npx tsc --noEmit || { echo "❌ Typecheck failed — aborting release"; exit 1; }
log_info "Running tests..."
npx vitest run lib.test.ts lib.version.test.ts lib.packaging.test.ts || { echo "❌ Tests failed — aborting release"; exit 1; }
log_info "✅ All checks passed"

CURRENT=$(node -e "console.log(require('./package.json').version)")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  *) echo "Usage: $0 [patch|minor|major] [\"message\"]"; exit 1 ;;
esac
NEXT="$MAJOR.$MINOR.$PATCH"

log_info "Bumping $CURRENT → $NEXT ($BUMP bump)"

# Update package.json
node -e "
const fs = require('fs');
const j = JSON.parse(fs.readFileSync('package.json', 'utf8'));
j.version = '$NEXT';
fs.writeFileSync('package.json', JSON.stringify(j, null, 2) + '\n');
console.log('  updated package.json -> v' + j.version);
"

git add -A
git commit -m "Release v$NEXT${MSG:+: $MSG}" || true
git tag -d "v$NEXT" 2>/dev/null || true
git tag -a "v$NEXT" -m "${MSG:-Release v$NEXT}"

log_info "Tagged v$NEXT"
log_info "Pushing to remote..."

git push -u origin main && git push origin "v$NEXT" || log_warn "Push failed"

log_info "=== Done: released v$NEXT ==="

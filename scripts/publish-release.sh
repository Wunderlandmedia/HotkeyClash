#!/bin/bash
set -euo pipefail

# HotkeyClash release publisher.
#
# Publishes the notarized artifacts produced by build-release.sh to a GitHub
# Release. Run this after you have built, installed, and tested the DMG.
#
# Prerequisites:
#   - gh CLI installed and authenticated:  brew install gh && gh auth login
#   - Notarized artifacts already built:   ./scripts/build-release.sh
#
# Usage:
#   ./scripts/publish-release.sh                   # draft release, version inferred from artifacts
#   ./scripts/publish-release.sh --version 0.2.0   # explicit version
#   ./scripts/publish-release.sh --publish         # publish immediately instead of a draft
#   ./scripts/publish-release.sh --notes-file NOTES.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="HotkeyClash"
OUTPUT_DIR="$PROJECT_DIR/build/release"

DRAFT=true
VERSION=""
NOTES_FILE=""

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --publish)
            DRAFT=false
            shift
            ;;
        --notes-file)
            NOTES_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--version X.Y.Z] [--publish] [--notes-file FILE]"
            echo ""
            echo "Options:"
            echo "  --version X.Y.Z    Release version (default: inferred from build/release/*.dmg)"
            echo "  --publish          Publish immediately (default: create a draft to review)"
            echo "  --notes-file FILE   Use FILE for release notes (default: auto-generate from commits)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log() { echo "==> $1"; }
fail() { echo "Error: $1" >&2; exit 1; }

# --- Tooling ---

command -v gh >/dev/null 2>&1 || fail "gh CLI not found. Install with: brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated. Run: gh auth login"

# --- Determine version ---

if [[ -z "$VERSION" ]]; then
    shopt -s nullglob
    dmgs=("$OUTPUT_DIR/$APP_NAME"-*.dmg)
    shopt -u nullglob
    [[ ${#dmgs[@]} -eq 1 ]] || fail "Could not infer version: expected exactly one $APP_NAME-*.dmg in $OUTPUT_DIR (found ${#dmgs[@]}). Pass --version."
    base="$(basename "${dmgs[0]}")"
    VERSION="${base#"$APP_NAME"-}"
    VERSION="${VERSION%.dmg}"
fi

TAG="v$VERSION"
DMG="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$OUTPUT_DIR/$APP_NAME-$VERSION.zip"
SUMS="$OUTPUT_DIR/SHA256SUMS.txt"

log "Preparing release $TAG"

# --- Artifacts present ---

for f in "$DMG" "$ZIP" "$SUMS"; do
    [[ -f "$f" ]] || fail "Missing artifact: $f. Run ./scripts/build-release.sh first."
done

# --- Verify notarization ---

log "Verifying notarization..."
xcrun stapler validate "$DMG" >/dev/null 2>&1 \
    || fail "DMG is not notarized/stapled: $DMG. Build without --skip-notarize."
if ! spctl -a -t open --context context:primary-signature "$DMG" >/dev/null 2>&1; then
    echo "Warning: Gatekeeper assessment of the DMG was inconclusive (continuing)."
fi

# --- Git preflight ---

cd "$PROJECT_DIR"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a git repository."

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || echo "Warning: not on main (currently on $branch)."

[[ -z "$(git status --porcelain)" ]] \
    || fail "Working tree has uncommitted changes. Commit them so the release matches the tagged source."

git fetch origin "$branch" --quiet || true
if [[ -n "$(git log "origin/$branch..HEAD" --oneline 2>/dev/null)" ]]; then
    fail "Local $branch has unpushed commits. Push them first: git push"
fi

# --- Tag ---

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists locally; reusing it."
else
    log "Creating tag $TAG"
    git tag -a "$TAG" -m "$APP_NAME $VERSION"
fi
git push origin "$TAG"

# --- Notes ---

notes_args=(--generate-notes)
if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || fail "Notes file not found: $NOTES_FILE"
    notes_args=(--notes-file "$NOTES_FILE")
fi

draft_args=()
if $DRAFT; then
    draft_args=(--draft)
fi

# --- Create or update the release ---

if gh release view "$TAG" >/dev/null 2>&1; then
    log "Release $TAG already exists; uploading artifacts (overwriting same names)..."
    gh release upload "$TAG" "$DMG" "$ZIP" "$SUMS" --clobber
else
    log "Creating release $TAG"
    gh release create "$TAG" "$DMG" "$ZIP" "$SUMS" \
        --title "$APP_NAME $VERSION" \
        "${notes_args[@]}" \
        "${draft_args[@]}"
fi

url="$(gh release view "$TAG" --json url -q .url 2>/dev/null || true)"
echo ""
log "Done. ${url:-Release $TAG}"
if $DRAFT; then
    echo "This is a DRAFT. Review the notes on GitHub and click Publish,"
    echo "or re-run with --publish to release immediately."
fi

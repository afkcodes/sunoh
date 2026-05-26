#!/usr/bin/env bash
#
# scripts/release.sh — cut a sunoh. release end-to-end.
#
# What it does, in order:
#   1. Validates the working tree is clean, gh is logged in, the keystore is
#      wired, and the sibling sunoh_next repo (for the update manifest) is
#      present + clean.
#   2. Reads the current `version: X.Y.Z+N` from pubspec.yaml.
#   3. Bumps it per the argument (patch / minor / major / explicit version).
#      The buildNumber is always incremented.
#   4. Lets you write release notes in $EDITOR (or accept --notes-file).
#   5. Confirms once.
#   6. Writes pubspec.yaml, commits, tags `vX.Y.Z`.
#   7. Builds a signed release APK (optionally --split-per-abi).
#   8. Pushes the commit + tag to `origin`.
#   9. `gh release create vX.Y.Z` with the APK(s) attached and the notes.
#  10. Updates ../sunoh_next/public/.well-known/sunoh-updates.json with the
#      new version/url/notes, commits + pushes that repo (unless
#      --skip-manifest).
#
# Usage:
#   scripts/release.sh patch                 # 1.0.0+1 → 1.0.1+2
#   scripts/release.sh minor                 # 1.0.0+1 → 1.1.0+2
#   scripts/release.sh major                 # 1.0.0+1 → 2.0.0+2
#   scripts/release.sh 1.2.3                 # explicit
#   scripts/release.sh patch --notes-file release-notes.md
#   scripts/release.sh patch --split-apks    # arm64 / armv7 / x86_64 separately
#   scripts/release.sh patch --dry-run       # print intended actions, change nothing
#   scripts/release.sh patch --skip-manifest # don't touch sunoh_next

set -euo pipefail

# ── Defaults ───────────────────────────────────────────────────────────────
BUMP_ARG=""
NOTES_FILE=""
SPLIT_APKS=0
DRY_RUN=0
SKIP_MANIFEST=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUNOH_NEXT_DIR="${SUNOH_NEXT_DIR:-$REPO_ROOT/../sunoh_next}"
MANIFEST_PATH="public/.well-known/sunoh-updates.json"

# ── Colors (only when stdout is a TTY) ─────────────────────────────────────
if [[ -t 1 ]]; then
  C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_DIM=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi

log()  { printf '%s[release]%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn() { printf '%s[release]%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_YELLOW" "$*" "$C_RESET"; }
err()  { printf '%s[release]%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2; }
ok()   { printf '%s[release]%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_GREEN" "$*" "$C_RESET"; }

run() {
  if (( DRY_RUN )); then
    printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
  else
    eval "$@"
  fi
}

# ── Args ────────────────────────────────────────────────────────────────────
while (( $# > 0 )); do
  case "$1" in
    --notes-file)
      NOTES_FILE="$2"; shift 2 ;;
    --split-apks)
      SPLIT_APKS=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --skip-manifest)
      SKIP_MANIFEST=1; shift ;;
    -h|--help)
      sed -n '4,30p' "$0"; exit 0 ;;
    *)
      if [[ -z "$BUMP_ARG" ]]; then BUMP_ARG="$1"; shift
      else err "unexpected argument: $1"; exit 2
      fi
      ;;
  esac
done

if [[ -z "$BUMP_ARG" ]]; then
  err "missing bump argument (patch | minor | major | <X.Y.Z>)"
  exit 2
fi

cd "$REPO_ROOT"

# ── Pre-flight ──────────────────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  err "gh CLI not installed (https://cli.github.com)"; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  err "gh not authenticated — run 'gh auth login' first"; exit 1
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  err "no 'origin' remote configured — set one with 'git remote add origin git@github.com:<owner>/<repo>.git'"
  exit 1
fi
if [[ ! -f android/key.properties ]]; then
  err "android/key.properties missing — release builds would fall back to debug signing"; exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  err "working tree is dirty — commit or stash before releasing"
  git status --short
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 needed for manifest update (or pass --skip-manifest)"; exit 1
fi

# ── Read current version ────────────────────────────────────────────────────
CURRENT_LINE="$(grep -E '^version:' pubspec.yaml || true)"
if [[ -z "$CURRENT_LINE" ]]; then
  err "no 'version:' line in pubspec.yaml"; exit 1
fi
# CURRENT_LINE is "version: X.Y.Z+N"
CURRENT_VERSION_FULL="${CURRENT_LINE#version: }"
CURRENT_SEMVER="${CURRENT_VERSION_FULL%+*}"
CURRENT_BUILD="${CURRENT_VERSION_FULL#*+}"
if [[ "$CURRENT_BUILD" == "$CURRENT_VERSION_FULL" ]]; then
  CURRENT_BUILD=0
fi

IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_SEMVER"

case "$BUMP_ARG" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  *)
    if [[ "$BUMP_ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      IFS='.' read -r MAJOR MINOR PATCH <<<"$BUMP_ARG"
    else
      err "unrecognised bump: '$BUMP_ARG' (expected patch|minor|major|X.Y.Z)"
      exit 2
    fi
    ;;
esac

NEW_SEMVER="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_VERSION="${NEW_SEMVER}+${NEW_BUILD}"
TAG="v${NEW_SEMVER}"

log "current: ${CURRENT_VERSION_FULL}"
log "new:     ${NEW_VERSION}  (tag ${TAG})"

# ── Notes ───────────────────────────────────────────────────────────────────
NOTES=""
if [[ -n "$NOTES_FILE" ]]; then
  [[ -r "$NOTES_FILE" ]] || { err "notes file not readable: $NOTES_FILE"; exit 1; }
  NOTES="$(cat "$NOTES_FILE")"
else
  TMP_NOTES="$(mktemp -t sunoh-release-XXXX.md)"
  trap 'rm -f "$TMP_NOTES"' EXIT
  cat >"$TMP_NOTES" <<EOF
# Release notes for ${TAG}
# Lines starting with '#' are ignored. Save + close to continue;
# leave the file empty to abort.

EOF
  "${EDITOR:-vi}" "$TMP_NOTES"
  NOTES="$(grep -v '^#' "$TMP_NOTES" | sed -e '1{/^$/d}' -e '${/^$/d}')"
  if [[ -z "$NOTES" ]]; then
    err "empty notes — aborting"; exit 1
  fi
fi

# Compact summary for the manifest (first non-empty line).
NOTES_SUMMARY="$(printf '%s\n' "$NOTES" | awk 'NF{print; exit}')"

# Trim release URL ahead of time so we can put it in the manifest.
ORIGIN_URL="$(git remote get-url origin)"
# Convert SSH form (git@github.com:owner/repo.git) → https://github.com/owner/repo
if [[ "$ORIGIN_URL" =~ ^git@github\.com:(.+)\.git$ ]]; then
  GH_SLUG="${BASH_REMATCH[1]}"
elif [[ "$ORIGIN_URL" =~ ^https://github\.com/(.+)(\.git)?$ ]]; then
  GH_SLUG="${BASH_REMATCH[1]%.git}"
else
  err "couldn't parse GitHub slug from origin URL: $ORIGIN_URL"; exit 1
fi
RELEASE_URL="https://github.com/${GH_SLUG}/releases/tag/${TAG}"

# ── Confirm ────────────────────────────────────────────────────────────────
printf '\n%s%sAbout to release:%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
printf '  %-12s %s\n' 'version' "$NEW_VERSION"
printf '  %-12s %s\n' 'tag'     "$TAG"
printf '  %-12s %s\n' 'repo'    "$GH_SLUG"
printf '  %-12s %s\n' 'apks'    "$([[ $SPLIT_APKS == 1 ]] && echo 'split-per-abi' || echo 'single fat')"
printf '  %-12s %s\n' 'manifest' "$([[ $SKIP_MANIFEST == 1 ]] && echo 'skipped' || echo "$SUNOH_NEXT_DIR/$MANIFEST_PATH")"
printf '  %-12s %s\n' 'dry-run' "$([[ $DRY_RUN == 1 ]] && echo 'yes' || echo 'no')"
printf '\nNotes:\n%s\n\n' "$NOTES"
read -rp "Proceed? [y/N] " ans
[[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { warn "aborted"; exit 1; }

# ── Manifest pre-flight (so we fail BEFORE the long build if needed) ───────
if (( SKIP_MANIFEST == 0 )); then
  if [[ ! -d "$SUNOH_NEXT_DIR" ]]; then
    err "sunoh_next not found at $SUNOH_NEXT_DIR — pass --skip-manifest or set SUNOH_NEXT_DIR"; exit 1
  fi
  if [[ ! -f "$SUNOH_NEXT_DIR/$MANIFEST_PATH" ]]; then
    err "manifest missing at $SUNOH_NEXT_DIR/$MANIFEST_PATH"; exit 1
  fi
  if [[ -n "$(git -C "$SUNOH_NEXT_DIR" status --porcelain)" ]]; then
    err "sunoh_next working tree is dirty — commit or stash there first"; exit 1
  fi
fi

# ── Bump pubspec ───────────────────────────────────────────────────────────
log "writing pubspec.yaml: $NEW_VERSION"
if (( DRY_RUN == 0 )); then
  # Replace only the version line. Anchored to BOL so we never trip on
  # the comment lines above that mention 'version'.
  python3 - <<PY
import re, pathlib
p = pathlib.Path('pubspec.yaml')
t = p.read_text()
t = re.sub(r'(?m)^version:\s*.*$', 'version: ${NEW_VERSION}', t, count=1)
p.write_text(t)
PY
fi

# ── Build APK(s) ───────────────────────────────────────────────────────────
log "running flutter build apk --release$([[ $SPLIT_APKS == 1 ]] && echo ' --split-per-abi')"
if (( SPLIT_APKS )); then
  run "flutter build apk --release --split-per-abi"
  APKS=(
    "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    "build/app/outputs/flutter-apk/app-x86_64-release.apk"
  )
else
  run "flutter build apk --release"
  APKS=( "build/app/outputs/flutter-apk/app-release.apk" )
fi

if (( DRY_RUN == 0 )); then
  for f in "${APKS[@]}"; do
    [[ -f "$f" ]] || { err "expected APK missing: $f"; exit 1; }
  done
fi

# ── Commit + tag + push ────────────────────────────────────────────────────
log "git commit + tag $TAG"
run "git add pubspec.yaml"
run "git commit -m 'Release $TAG'"
run "git tag -a $TAG -m 'Release $TAG'"
run "git push origin HEAD"
run "git push origin $TAG"

# ── GitHub release ─────────────────────────────────────────────────────────
log "creating GitHub release $TAG with $(printf '%d' ${#APKS[@]}) APK asset(s)"
NOTES_TMP="$(mktemp -t sunoh-relnotes-XXXX.md)"
printf '%s\n' "$NOTES" >"$NOTES_TMP"
run "gh release create $TAG ${APKS[*]} --title '$TAG' --notes-file $NOTES_TMP"
rm -f "$NOTES_TMP"

# ── Update sunoh_next manifest ─────────────────────────────────────────────
if (( SKIP_MANIFEST == 0 )); then
  log "updating $SUNOH_NEXT_DIR/$MANIFEST_PATH"
  if (( DRY_RUN == 0 )); then
    python3 - <<PY
import json, pathlib
p = pathlib.Path("${SUNOH_NEXT_DIR}/${MANIFEST_PATH}")
data = json.loads(p.read_text())
data["version"] = "${NEW_SEMVER}"
data["buildNumber"] = ${NEW_BUILD}
data["url"] = "${RELEASE_URL}"
notes = ${NOTES_SUMMARY@Q}
data["notes"] = notes
p.write_text(json.dumps(data, indent=2) + "\n")
PY
  fi
  run "git -C '$SUNOH_NEXT_DIR' add '$MANIFEST_PATH'"
  run "git -C '$SUNOH_NEXT_DIR' commit -m 'Bump update manifest to $TAG'"
  run "git -C '$SUNOH_NEXT_DIR' push"
  log "manifest pushed — remember to redeploy sunoh_next so the JSON goes live"
fi

ok "release $TAG done."
log "release URL: $RELEASE_URL"

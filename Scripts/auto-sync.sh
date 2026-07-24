#!/usr/bin/env bash
set -euo pipefail

# Auto-sync upstream → main → rebase sync branch → build → push
# Usage: make sync  (or: bash scripts/auto-sync.sh)

SYNC_BRANCH="sync/upstream-2026q2"
REPORT=""

log()  { echo "▸ $*"; }
warn() { echo "⚠ $*" >&2; }
die()  { echo "✗ $*" >&2; exit 1; }

add_report() { REPORT="${REPORT}${1}\n"; }

print_report() {
    [ -z "$REPORT" ] && return
    echo ""
    echo "=== Sync Report ==="
    printf "%b" "$REPORT"
}

# ── Conflict resolvers (defined before use) ────────────────────────

resolve_pbxproj() {
    local file="$1"
    log "  Auto-resolving pbxproj: $file"

    # Rule 1: DEVELOPMENT_TEAM conflicts → keep HEAD (no team ID)
    perl -0777 -i -pe '
        s/<<<<<<< HEAD\n=======\n\s*DEVELOPMENT_TEAM = [^;]*;\n>>>>>>> [^\n]*\n//g;
    ' "$file"

    # Rule 2: additive deps — keep both sides (delete conflict markers only)
    perl -0777 -i -pe '
        s/<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n/$1$2/gs;
    ' "$file"

    add_report "AUTO: $file (pbxproj rules)"
}

resolve_package_resolved() {
    local file="$1"
    log "  Auto-resolving Package.resolved: $file"
    git checkout --theirs "$file" 2>/dev/null || true
    add_report "AUTO: $file (checkout --theirs + re-resolve)"
}

# ── Step 0: stash uncommitted changes ─────────────────────────────
STASHED=false
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
    log "Stashing uncommitted changes..."
    git stash push -m "auto-sync: pre-sync stash" -q
    STASHED=true
fi

cleanup() {
    if [ "$STASHED" = true ]; then
        log "Restoring stashed changes..."
        git stash pop -q 2>/dev/null || warn "Stash pop failed — run 'git stash pop' manually"
    fi
}
trap cleanup EXIT

# ── Step 1: fetch ──────────────────────────────────────────────────
log "Fetching upstream..."
git fetch upstream -q
git fetch origin -q

# ── Step 2: check for new commits ─────────────────────────────────
AHEAD=$(git rev-list --count main..upstream/main)
# ponytail: also check the sync branch itself — main can already equal
# upstream/main (e.g. a prior run fast-forwarded it) while the sync
# branch still hasn't been rebased onto it.
SYNC_BEHIND=$(git rev-list --count "$SYNC_BRANCH"..main)
if [ "$AHEAD" = "0" ] && [ "$SYNC_BEHIND" = "0" ]; then
    log "已是最新，無需同步。"
    exit 0
fi
log "上游有 $AHEAD 個新 commit（$SYNC_BRANCH 落後 main $SYNC_BEHIND 個 commit）"
add_report "New upstream commits: $AHEAD; $SYNC_BRANCH behind main: $SYNC_BEHIND"

# ── Step 3: fast-forward main (without checkout) ──────────────────
log "Fast-forwarding main to upstream/main..."
if ! git push . upstream/main:main -q 2>/dev/null; then
    die "main 無法 fast-forward，需要手動處理"
fi
git push origin main -q
add_report "main fast-forwarded to upstream/main"

# ── Step 4: rebase sync branch ────────────────────────────────────
log "Rebasing $SYNC_BRANCH onto main..."
# Ensure we're on the sync branch
git checkout "$SYNC_BRANCH" -q 2>/dev/null || true

CONFLICTS_RESOLVED=0

if git rebase main 2>/dev/null; then
    log "Rebase 乾淨通過"
    add_report "Rebase: clean (no conflicts)"
else
    log "Rebase 有衝突，嘗試自動解決..."

    while true; do
        CONFLICTED_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
        [ -z "$CONFLICTED_FILES" ] && break

        CAN_AUTO_RESOLVE=true

        while IFS= read -r file; do
            case "$file" in
                *.pbxproj)
                    resolve_pbxproj "$file"
                    ;;
                *Package.resolved)
                    resolve_package_resolved "$file"
                    ;;
                *)
                    warn "無法自動解決衝突: $file"
                    add_report "MANUAL: $file"
                    CAN_AUTO_RESOLVE=false
                    ;;
            esac
        done <<< "$CONFLICTED_FILES"

        if [ "$CAN_AUTO_RESOLVE" = false ]; then
            git rebase --abort 2>/dev/null || true
            add_report "Rebase: ABORTED (manual conflicts)"
            print_report
            die "有衝突需要手動解決，rebase 已 abort"
        fi

        echo "$CONFLICTED_FILES" | xargs git add
        CONFLICTS_RESOLVED=$((CONFLICTS_RESOLVED + 1))

        GIT_EDITOR=true git rebase --continue 2>/dev/null || continue
        break
    done

    [ "$CONFLICTS_RESOLVED" -gt 0 ] && add_report "Rebase: $CONFLICTS_RESOLVED conflict round(s) auto-resolved"
fi

# ── Step 5: resolve SPM packages ──────────────────────────────────
log "Resolving SPM packages..."
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -resolvePackageDependencies -quiet 2>/dev/null || true

# ── Step 6: build ─────────────────────────────────────────────────
log "Building..."
if make build; then
    add_report "Build: SUCCESS"
else
    add_report "Build: FAILED"
    print_report
    die "Build 失敗，請檢查 errors"
fi

# ── Step 7: push ──────────────────────────────────────────────────
log "Pushing $SYNC_BRANCH..."
git push origin "$SYNC_BRANCH" --force-with-lease -q
add_report "Push: force-with-lease to origin/$SYNC_BRANCH"

print_report
log "同步完成 ✓"

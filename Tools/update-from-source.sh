#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Updates a build that carries local changes: moves the current branch onto a
# newer upstream release, runs the tests, then builds and installs the result
# over /Applications/Vorssaint.app and reopens it. Settings and permissions are
# kept, because the bundle id and the local signing identity stay the same.
#
# The in-app updater calls this when its Update button is pressed in a build
# made from source (UpdateService.rebuildFromSource): installing the official
# download instead would remove the local changes.
#
#   Tools/update-from-source.sh                newest stable release
#   Tools/update-from-source.sh --beta         newest release, betas included
#   Tools/update-from-source.sh --tag v3.4.2   that release exactly
#   Tools/update-from-source.sh --rebuild      build and install even when nothing is new
#   Tools/update-from-source.sh --all-tests    run the project's whole test suite first
#   Tools/update-from-source.sh --skip-tests   leave the test run out
#   Tools/update-from-source.sh --restore-settings [file]
#                                              put back the settings saved before the last update
#
# Before every install the app's settings are saved to
# ~/Library/Application Support/Vorssaint Source Build/settings-backups, and
# after the new version has started the log lists which settings it changed.
set -euo pipefail

# Inside a function $0 is the function's name, so the checkout is found here.
REPOSITORY="${0:A:h:h}"
BUNDLE_ID="com.vorssaint.utils"
INSTALLED="/Applications/Vorssaint.app"
BACKUPS="$HOME/Library/Application Support/Vorssaint Source Build/settings-backups"
FROM_APP=0
# The suites that cover the local changes: the macro tests and the feature
# catalog they are registered in. They are what a move onto a new release can
# break. The rest of the project's suite is upstream's to keep green, and part
# of it lays out real windows, which fails whenever the screen is locked, as it
# may well be by the time an update started from the app gets this far.
LOCAL_SUITES=(keyboard features)

# Run from the app there is no terminal to read, so the outcome is a notification.
report() {
    echo "$1"
    if (( FROM_APP )); then
        /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Vorssaint update"' \
            -e 'end run' "$1" >/dev/null 2>&1 || true
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

# The app's settings as one file, named by the version that wrote them.
save_settings() {
    local label="$1" file
    mkdir -p "$BACKUPS"
    file="$BACKUPS/settings-$(date '+%Y%m%d-%H%M%S')-$label.plist"
    /usr/bin/defaults export "$BUNDLE_ID" "$file" 2>/dev/null || return 1
    # The newest twenty are plenty to go back to.
    local -a old
    old=("$BACKUPS"/settings-*.plist(Nom[21,-1]))
    (( ${#old} )) && command rm -f -- "${old[@]}"
    print -r -- "$file"
}

# Which settings the new version added, removed or changed. Names only: the
# values can hold private text such as snippets and macros.
report_settings_changes() {
    local before="$1" after="$2"
    /usr/bin/python3 -I - "$before" "$after" <<'PY'
import plistlib, sys
before = plistlib.load(open(sys.argv[1], "rb"))
after = plistlib.load(open(sys.argv[2], "rb"))
added = sorted(k for k in after if k not in before)
removed = sorted(k for k in before if k not in after)
changed = sorted(k for k in after if k in before and after[k] != before[k])
print(f"settings kept unchanged: {len([k for k in before if k in after and after[k] == before[k]])}")
for title, keys in (("added by the new version", added), ("removed", removed), ("changed", changed)):
    print(f"{title}: {len(keys)}" + ("" if not keys else "  " + ", ".join(keys)))
PY
}

restore_settings() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        local -a saved
        saved=("$BACKUPS"/settings-*-before-*.plist(Nom))
        file="${saved[1]:-}"
    fi
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "✗ No saved settings found in $BACKUPS." >&2
        return 1
    fi
    echo "▸ Restoring settings from ${file:t}…"
    /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 3
    /usr/bin/defaults import "$BUNDLE_ID" "$file"
    open "$INSTALLED"
    echo "✓ Settings restored and Vorssaint reopened."
}

# Everything runs from a function, so the whole file is read before the rebase
# below replaces it on disk.
main() {
    if [[ "${1:-}" == "--restore-settings" ]]; then
        restore_settings "${2:-}"
        return
    fi
    local beta=0 rebuild=0 tests=1 all_tests=0 target="" arg expect=""
    for arg in "$@"; do
        if [[ -n "$expect" ]]; then
            case "$expect" in
                tag) target="$arg" ;;
            esac
            expect=""
            continue
        fi
        case "$arg" in
            --beta) beta=1 ;;
            --rebuild) rebuild=1 ;;
            --skip-tests) tests=0 ;;
            --all-tests) all_tests=1 ;;
            --from-app) FROM_APP=1 ;;
            --tag) expect=tag ;;
            *) echo "Unknown option: $arg" >&2; return 2 ;;
        esac
    done

    cd "$REPOSITORY"

    local branch
    branch="$(git symbolic-ref --quiet --short HEAD || true)"
    if [[ -z "$branch" || "$branch" == "main" ]]; then
        report "✗ Update stopped: the checkout is not on the branch with your changes (now: ${branch:-detached HEAD})."
        return 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        report "✗ Update stopped: there are uncommitted changes on $branch. Commit them first."
        return 1
    fi

    echo "▸ Looking for a new release…"
    git fetch --quiet --tags origin
    if [[ -z "$target" ]]; then
        # A dash sorts a pre-release before its release, so v3.4.1 is newer than
        # v3.4.1-beta.5.
        local -a tags
        tags=("${(@f)$(git -c versionsort.suffix=- tag --list 'v[0-9]*' --sort=-v:refname)}")
        (( beta )) || tags=("${(@)tags:#*-*}")
        target="${tags[1]:-}"
    fi
    if [[ -z "$target" ]] || ! git rev-parse --quiet --verify "refs/tags/$target" >/dev/null; then
        report "✗ Update stopped: release ${target:-(none)} was not found."
        return 1
    fi

    if git merge-base --is-ancestor "$target" HEAD; then
        echo "✓ $branch already includes $target."
    else
        (( FROM_APP )) && report "Rebuilding Vorssaint $target with your changes. This takes a few minutes; the app restarts on its own."
        echo "▸ Moving $branch onto $target…"
        if ! git rebase "$target"; then
            # Left half-done, the checkout could not build anything at all.
            git rebase --abort || true
            report "✗ Update stopped: your changes overlap with what $target changed. Nothing was installed."
            return 1
        fi
    fi

    # What is installed is compared with what this checkout would build, so a
    # run that stopped after the move above still installs on the next try.
    local wanted installed
    wanted="$(plist_value Resources/Info.plist CFBundleShortVersionString) ($(plist_value Resources/Info.plist CFBundleVersion))"
    installed="$(plist_value "$INSTALLED/Contents/Info.plist" CFBundleShortVersionString) ($(plist_value "$INSTALLED/Contents/Info.plist" CFBundleVersion))"
    if [[ "$wanted" == "$installed" ]] && (( ! rebuild )); then
        echo "✓ Vorssaint $installed is already installed."
        /usr/bin/defaults write "$BUNDLE_ID" sourceCheckoutPath -string "$REPOSITORY"
        return 0
    fi

    if (( tests )); then
        local suite known
        if (( all_tests )); then
            ./build.sh --test || suite="the full suite"
        else
            known="$(./build.sh --list-tests 2>/dev/null || true)"
            for suite in "${LOCAL_SUITES[@]}"; do
                # A suite upstream renamed is skipped rather than failing the update.
                if [[ "$known" != *"$suite"* ]]; then
                    echo "  (no '$suite' test suite in this release; skipped)"
                    suite=""
                    continue
                fi
                ./build.sh --test-suite="$suite" || break
                suite=""
            done
        fi
        if [[ -n "${suite:-}" ]]; then
            report "✗ Update stopped: tests ($suite) failed on $target with your changes. Nothing was installed."
            return 1
        fi
    fi

    local before=""
    before="$(save_settings "before-${wanted%% *}")" || echo "  (settings could not be saved; continuing)"
    [[ -n "$before" ]] && echo "▸ Settings saved to ${before:t}"

    if ! ./build.sh --install; then
        report "✗ Update stopped: the build failed. The previous version may need reinstalling with --rebuild."
        return 1
    fi
    # Where the app finds this script the next time its Update button is pressed.
    /usr/bin/defaults write "$BUNDLE_ID" sourceCheckoutPath -string "$REPOSITORY"
    open "$INSTALLED"
    report "✓ Vorssaint ${wanted%% *} with $branch installed and running."

    # The new version settles its settings on first launch; then say what moved.
    if [[ -n "$before" ]]; then
        sleep 20
        local after
        if after="$(save_settings "after-${wanted%% *}")"; then
            echo "▸ What the new version did to your settings:"
            report_settings_changes "$before" "$after" | sed 's/^/  /'
        fi
    fi
}

main "$@"

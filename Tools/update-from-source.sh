#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Updates a build that carries local changes: moves the current branch onto the
# newest upstream release, runs the tests, then builds and installs the result
# over /Applications/Vorssaint.app. Settings and permissions are kept, because
# the bundle id and the local signing identity stay the same.
#
# The in-app updater installs the official release, which has none of the local
# changes, so a build made from source never updates itself (AppInfo.isSourceBuild).
# This script is how it gets a new version instead.
#
#   Tools/update-from-source.sh              newest stable release
#   Tools/update-from-source.sh --beta       newest release, betas included
#   Tools/update-from-source.sh --rebuild    build and install even when nothing is new
#   Tools/update-from-source.sh --skip-tests leave the test run out
set -euo pipefail

# Inside a function $0 is the function's name, so the checkout is found here.
REPOSITORY="${0:A:h:h}"

# Everything runs from a function, so the whole file is read before the rebase
# below replaces it on disk.
main() {
    local beta=0 rebuild=0 tests=1 arg
    for arg in "$@"; do
        case "$arg" in
            --beta) beta=1 ;;
            --rebuild) rebuild=1 ;;
            --skip-tests) tests=0 ;;
            *) echo "Unknown option: $arg" >&2; return 2 ;;
        esac
    done

    cd "$REPOSITORY"

    local branch
    branch="$(git symbolic-ref --quiet --short HEAD || true)"
    if [[ -z "$branch" || "$branch" == "main" ]]; then
        echo "✗ Check out the branch that holds your changes first (now: ${branch:-detached HEAD})." >&2
        return 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "✗ Uncommitted changes on $branch. Commit them first, so the update can carry them over." >&2
        return 1
    fi

    echo "▸ Looking for a new release…"
    git fetch --quiet --tags origin
    # A dash sorts a pre-release before its release, so v3.4.1 is newer than
    # v3.4.1-beta.5.
    local -a tags
    tags=("${(@f)$(git -c versionsort.suffix=- tag --list 'v[0-9]*' --sort=-v:refname)}")
    (( beta )) || tags=("${(@)tags:#*-*}")
    local target="${tags[1]:-}"
    if [[ -z "$target" ]]; then
        echo "✗ No release tag found." >&2
        return 1
    fi

    if git merge-base --is-ancestor "$target" HEAD; then
        echo "✓ $branch already includes $target."
        (( rebuild )) || return 0
    else
        echo "▸ Moving $branch onto $target…"
        if ! git rebase "$target"; then
            echo "" >&2
            echo "✗ Your changes overlap with what $target changed." >&2
            echo "  The installed app was not touched. Resolve the listed files, then run" >&2
            echo "  'git rebase --continue' and this script again, or 'git rebase --abort' to go back." >&2
            return 1
        fi
    fi

    if (( tests )); then
        ./build.sh --test
    fi
    ./build.sh --install
    open "/Applications/Vorssaint.app"
    echo "✓ Vorssaint $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist) with $branch installed and running."
}

main "$@"

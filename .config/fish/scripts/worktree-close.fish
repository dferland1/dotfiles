#!/usr/bin/env fish

function check_worktree_clean --argument-names current
    set -l changes (git -C "$current" status --porcelain --untracked-files=all)
    or return $status
    if test (count $changes) -gt 0
        printf 'Refusing to remove a worktree with uncommitted or untracked files:\n' >&2
        printf '%s\n' $changes >&2
        return 1
    end
end

function worktree-close
    if not set -q REX_SESSION; or not set -q REX_BLOCK
        printf 'Run this script in the Rex worktree tab you want to close.\n' >&2
        return 1
    end

    set -l current (git rev-parse --show-toplevel)
    or return $status
    set -l records (git worktree list --porcelain -z | string split0)
    or return $status
    set -l main_repo (string replace 'worktree ' '' -- "$records[1]")
    if test "$current" = "$main_repo"
        printf 'Refusing to remove the main checkout.\n' >&2
        return 1
    end

    set -l block_json (rex block inspect "$REX_BLOCK" -s "$REX_SESSION" --json)
    or return $status
    set -l window_id (printf '%s\n' $block_json | jq -er '.block.window_id')
    or return $status

    cd "$current"
    or return $status
    printf 'Remove worktree: %s\n\n' "$current"
    printf 'This runs tilt down if a Tiltfile exists, closes every pane in this tab,\nand removes the checkout. The Git branch is kept.\n\n'
    read -l -P 'Continue? [y/N] ' confirm
    if test $status -ne 0; or not contains -- "$confirm" y Y
        rex block close -s "$REX_SESSION" "$REX_BLOCK"
        return $status
    end

    check_worktree_clean "$current"
    or return $status
    if test -e "$current/Tiltfile"
        tilt down -f "$current/Tiltfile"
        or return $status
    else
        printf 'No Tiltfile found; skipping tilt down.\n'
    end
    check_worktree_clean "$current"
    or return $status

    cd "$main_repo"
    or return $status
    set -l session_json (rex session inspect "$REX_SESSION" --json)
    or return $status
    set -l panes (printf '%s\n' $session_json | jq -r \
        --arg window "$window_id" --arg prompt "$REX_BLOCK" \
        '.windows[] | select(.window_id == $window) | .layers[].blocks[] | select(.block_id != $prompt) | .block_id')
    or return $status
    for pane in $panes
        rex block close -s "$REX_SESSION" "$pane"
        or return $status
    end

    git worktree remove -- "$current"
    or return $status
    rex window close -s "$REX_SESSION" "$window_id"
end

trap 'rex block close -s "$REX_SESSION" "$REX_BLOCK"; exit 0' INT
worktree-close

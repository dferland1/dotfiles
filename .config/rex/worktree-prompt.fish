#!/usr/bin/env fish

function cancel
    rex block close -s "$REX_SESSION" "$REX_BLOCK"
    exit 0
end
trap cancel INT

set -l payload "$argv[1]"
set -l operation (printf '%s' "$payload" | jq -er '.operation')
or exit $status
if test "$operation" = create
    set -l branch (printf '%s' "$payload" | jq -r '.branch // ""')
    if test -z "$branch"
        printf 'New worktree\n\nEnter a Git branch name. Empty input or Ctrl+C cancels.\n\n'
        read -l -P 'Branch: ' branch
        or cancel
        test -n "$branch"
        or cancel
        set payload (printf '%s' "$payload" | jq -c --arg branch "$branch" '. + {branch: $branch}')
        or exit $status
    end
else
    printf 'Remove worktree at: %s\n\n' (printf '%s' "$payload" | jq -r '.cwd')
    printf 'This runs tilt down if a Tiltfile exists, closes every pane in this tab,\nand removes the checkout. The Git branch is kept.\n\n'
    read -l -P 'Continue? [y/N] ' confirm
    or cancel
    contains -- "$confirm" y Y
    or cancel
end

rex do -e 'local worktree = dofile(rex.args.config_home .. "/rex/worktree.lua"); return worktree.run(rex.args)' --args "$payload"

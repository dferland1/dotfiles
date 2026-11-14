#!/usr/bin/env fish

function worktree-create
    if not set -q REX_SESSION; or not set -q REX_BLOCK
        printf 'Run this script in a Rex terminal.\n' >&2
        return 1
    end

    if test (count $argv) -eq 2; and test "$argv[1]" = --prompt
        trap 'exit 0' INT
        printf 'New worktree\n\nEnter a Git branch name. Empty input or Ctrl+C cancels.\n\n'
        read -l -P 'Branch: ' branch
        or return 0
        test -n "$branch"
        or return 0

        if not rex do -s "$REX_SESSION" -b "$argv[2]" new_worktree "branch=$branch"
            read -l -P 'Press Enter to close.'
        end
        return 0
    end

    if test (count $argv) -ne 1; or test -z "$argv[1]"
        printf 'Usage: worktree-create.fish <branch-name>\n' >&2
        return 1
    end
    set -l branch "$argv[1]"
    if string match -q -- '-*' "$branch"
        printf 'Branch names cannot start with a dash.\n' >&2
        return 1
    end
    git check-ref-format "refs/heads/$branch"
    or return $status

    set -l records (git worktree list --porcelain -z | string split0)
    or return $status
    set -l main_repo (string replace 'worktree ' '' -- "$records[1]")
    set -l project (basename "$main_repo")
    set -l worktree (dirname "$main_repo")/.worktrees/"$project"/"$branch"
    if test -e "$worktree"; or test -L "$worktree"
        printf 'Worktree path already exists: %s\n' "$worktree" >&2
        return 1
    end

    if git show-ref --verify --quiet "refs/heads/$branch"
        git worktree add -- "$worktree" "$branch"
        or return $status
    else
        set -l branch_status $status
        test "$branch_status" -eq 1
        or return "$branch_status"
        git worktree add -b "$branch" -- "$worktree" HEAD
        or return $status
    end

    cd "$worktree"
    or return $status
    set -l block_json (rex block inspect "$REX_BLOCK" -s "$REX_SESSION" --json)
    or return $status
    set -l window_id (printf '%s\n' $block_json | jq -er '.block.window_id')
    or return $status
    rex window rename -s "$REX_SESSION" "$window_id" "$project/$branch"
    or return $status
    rex focus -s "$REX_SESSION" "$window_id"
    or return $status
    exec fish -l
end

worktree-create $argv

#!/usr/bin/env fish

function worktree-create
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
        git worktree add -- "$worktree" "$branch" >&2
        or return $status
    else
        set -l branch_status $status
        test "$branch_status" -eq 1
        or return "$branch_status"
        git worktree add -b "$branch" -- "$worktree" HEAD >&2
        or return $status
    end

    jq -n --arg worktree "$worktree" --arg project "$project" --arg branch "$branch" \
        '{worktree: $worktree, project: $project, branch: $branch}'
end

worktree-create $argv

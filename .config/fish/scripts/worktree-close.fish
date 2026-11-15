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
    set -l phase close
    if test (count $argv) -gt 0
        switch "$argv[1]"
            case --prepare --remove
                set phase (string sub -s 3 -- "$argv[1]")
                set -e argv[1]
            case '-*'
                printf 'Unknown option: %s\n' "$argv[1]" >&2
                return 1
        end
    end
    if test (count $argv) -gt 1
        printf 'Usage: worktree-close.fish [--prepare|--remove] [worktree-path]\n' >&2
        return 1
    end
    set -l target .
    if test (count $argv) -eq 1
        set target "$argv[1]"
    end
    set -l current (git -C "$target" rev-parse --show-toplevel)
    or return $status
    set -l records (git -C "$current" worktree list --porcelain -z | string split0)
    or return $status
    set -l main_repo (string replace 'worktree ' '' -- "$records[1]")
    if test "$current" = "$main_repo"
        printf 'Refusing to remove the main checkout.\n' >&2
        return 1
    end
    check_worktree_clean "$current"
    or return $status

    if test "$phase" != remove
        cd "$current"
        or return $status
        if test -e Tiltfile
            tilt down -f "$current/Tiltfile" >&2
            or return $status
        else
            printf 'No Tiltfile found; skipping tilt down.\n' >&2
        end
        for compose_file in compose.yaml compose.yml docker-compose.yaml docker-compose.yml
            if test -f "$compose_file"
                docker compose down >&2
                or return $status
                break
            end
        end
        check_worktree_clean "$current"
        or return $status
    end

    if test "$phase" != prepare
        cd "$main_repo"
        or return $status
        git worktree remove -- "$current" >&2
        or return $status
    end
    jq -n --arg worktree "$current" --arg main_repo "$main_repo" \
        '{worktree: $worktree, main_repo: $main_repo}'
end

worktree-close $argv

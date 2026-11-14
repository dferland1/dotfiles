rex.bind("cmd+shift+h", "pane.focus", { direction = "left" })
rex.bind("cmd+shift+j", "pane.focus", { direction = "down" })
rex.bind("cmd+shift+k", "pane.focus", { direction = "up" })
rex.bind("cmd+shift+l", "pane.focus", { direction = "right" })
rex.unbind("alt+cmd+m")
rex.bind("cmd+shift+m", "pane.minimize_floating")

local worktree_command = [=[
set -euo pipefail

IFS= read -r -d '' main_record < <(git worktree list --porcelain -z)
main_repo=${main_record#worktree }
project=$(basename "$main_repo")

branch=${1:-}
if [[ -z "$branch" ]]; then
    read -r -p 'Worktree branch (empty to cancel): ' branch
fi
[[ -n "$branch" ]] || exit 0
case "$branch" in
    -*) printf 'Branch names cannot start with a dash.\n' >&2; exit 1 ;;
esac
git check-ref-format "refs/heads/$branch"

worktree="$(dirname "$main_repo")/.worktrees/$project/$branch"
if [[ -e "$worktree" || -L "$worktree" ]]; then
    printf 'Worktree path already exists: %s\n' "$worktree" >&2
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add -- "$worktree" "$branch"
else
    status=$?
    [[ "$status" -eq 1 ]] || exit "$status"
    git worktree add -b "$branch" -- "$worktree" HEAD
fi

cd "$worktree"
window_id=$(rex block inspect "$REX_BLOCK" --json | jq -er '.block.window_id')
rex window rename -s "$REX_SESSION" "$window_id" "$project/$branch"
exec "${SHELL:-/bin/sh}" -l
]=]

rex.action({
    name = "new_worktree",
    title = "New Worktree Tab",
    args = { branch = "string?" },
    run = function(ctx, args)
        local process, err = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
        if err ~= nil then error(err, 0) end
        local cwd = process.foreground and process.foreground.cwd
        if not cwd then error("Cannot determine the focused terminal's working directory", 0) end

        local window, window_err = rex.session.new_window({
            window_label = "New worktree",
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                options = {
                    cwd = cwd,
                    shell = "none",
                    command = { "bash", "-c", worktree_command, "new-worktree", args.branch or "" },
                    exit = { on_completion = false },
                },
            }),
        })
        if window_err ~= nil then error(window_err, 0) end
        return window
    end,
})

rex.bind("cmd+shift+t", "new_worktree")

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

branch=$1
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

local worktree_prompt = [=[
set -euo pipefail

trap 'exit 0' INT
printf 'New worktree\n\nEnter a Git branch name. Empty input or Ctrl+C cancels.\n\n'
read -r -p 'Branch: ' branch || exit 0
[[ -n "$branch" ]] || exit 0

if ! rex do -s "$1" -b "$2" new_worktree "branch=$branch"; then
    printf '\nPress Enter to close.'
    read -r || exit 0
fi
]=]

rex.action({
    name = "new_worktree",
    title = "New Worktree Tab",
    args = { branch = "string?" },
    run = function(ctx, args)
        if not ctx.session_id or not ctx.block_id then
            error("Run this action from a terminal in a Rex session", 0)
        end
        local process, err = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
        if err ~= nil then error(err, 0) end
        local cwd = process.foreground and process.foreground.cwd
        if not cwd then error("Cannot determine the focused terminal's working directory", 0) end

        if not args.branch or args.branch == "" then
            local source, source_err = rex.session.describe_block({ block_id = ctx.block_id })
            if source_err ~= nil then error(source_err, 0) end
            local prompt, prompt_err = rex.session.new_layer({
                window_id = source.block.window_id,
                bounds = { 0.25, 0.39, 0.5, 0.22 },
                focus = true,
                layout = rex.layout.block({
                    flavor = "com.superlogical.terminal.shell",
                    label = "New worktree",
                    options = {
                        cwd = cwd,
                        shell = "none",
                        command = {
                            "bash", "-c", worktree_prompt, "worktree-prompt", ctx.session_id, ctx.block_id,
                        },
                        exit = { on_completion = true },
                    },
                }),
            })
            if prompt_err ~= nil then error(prompt_err, 0) end
            return prompt
        end

        local window, window_err = rex.session.new_window({
            window_label = "New worktree",
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                options = {
                    cwd = cwd,
                    shell = "none",
                    command = { "bash", "-c", worktree_command, "new-worktree", args.branch },
                    exit = { on_completion = false },
                },
            }),
        })
        if window_err ~= nil then error(window_err, 0) end
        return window
    end,
})

rex.bind("cmd+shift+t", "new_worktree")
